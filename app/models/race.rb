class Race < ApplicationRecord
  STATUSES = %w[upcoming active completed cancelled].freeze
  # How a finished race was officially decided, shown beside a historical replay.
  DECIDED_BY = %w[plurality majority_runoff ranked_choice approval top_two].freeze

  include Engageable

  belongs_to :election
  belongs_to :office
  has_many :candidacies, dependent: :destroy
  has_many :candidates, through: :candidacies, source: :citizen
  has_many :voter_race_baselines, dependent: :destroy
  has_many :voter_race_baseline_archives, dependent: :delete_all
  has_many :voter_race_preferences, dependent: :delete_all
  has_many :mountain_drafts, dependent: :delete_all
  has_many :public_mountains, dependent: :destroy
  has_many :mountain_ratings
  has_many :official_results, dependent: :destroy

  validates :status, presence: true, inclusion: { in: STATUSES }
  # An updateable fact about the source's list, kept out of the race's identity and code.
  validates :certification_status, inclusion: { in: %w[certified tentative unofficial] }, allow_nil: true
  validates :decided_by, inclusion: { in: DECIDED_BY }, allow_nil: true
  validate :office_matches_election_jurisdiction

  scope :upcoming, -> { where(status: "upcoming") }
  scope :active, -> { where(status: "active") }
  scope :completed, -> { where(status: "completed") }
  scope :mock, -> { joins(:election).merge(Election.mock) }
  scope :historical, -> { joins(:election).merge(Election.historical) }
  scope :real, -> { joins(:election).merge(Election.real) }
  scope :recent, -> { joins(:election).order("elections.election_date DESC") }
  scope :open_to_rating, -> { where(status: Election::OPEN_STATUSES) }
  # Races with at least one saved mountain, so their results have something to show.
  scope :with_mountains, -> { where(id: VoterRaceBaseline.select(:race_id)) }
  scope :in_jurisdictions, ->(jurisdictions) { joins(:office).where(offices: { jurisdiction_id: jurisdictions.select(:id) }) }
  # The real races still open where a voter, or one residence, votes.
  scope :on_ballot_for, ->(holder) { real.open_to_rating.in_jurisdictions(holder.ballot_jurisdictions) }
  scope :in_place_named, ->(query) { in_jurisdictions(Jurisdiction.and_their_descendants(Jurisdiction.named_like(query))) }
  # Races a search for an office, election, candidate, or place finds.
  scope :findable, ->(query) { where(id: matching(query).select(:id)).or(where(id: in_place_named(query).select(:id))) }
  scope :with_full_details, -> { includes(:office, :candidates, :candidacies) }
  scope :with_candidacy_details, -> { includes(candidacies: [ :citizen, :ratings ]) }
  scope :with_office_context, -> { includes(office: :position) }
  scope :with_naming_details, -> { includes(election: :year, office: [ :position, { jurisdiction: :jurisdictionable } ]) }

  scope :in_state, ->(state) {
    state.jurisdiction ? joins(:office).where(offices: { jurisdiction_id: state.jurisdiction.self_and_descendants.select(:id) }) : none
  }
  scope :in_county, ->(county) {
    roots = Jurisdiction.where(jurisdictionable: county)
      .or(Jurisdiction.where(jurisdictionable_type: "Municipality", jurisdictionable_id: county.municipalities.select(:id)))
    in_jurisdictions(Jurisdiction.and_their_descendants(roots))
  }
  scope :national, -> { joins(:office).merge(Office.national) }
  scope :state_level, -> { joins(:office).merge(Office.state_level) }
  scope :local, -> { joins(:office).merge(Office.local) }
  scope :at_level, ->(level) {
    case level
    when "national" then national
    when "state" then state_level
    when "local" then local
    end
  }

  scope :matching, ->(query) {
    pattern = "%#{sanitize_sql_like(query.strip)}%"
    candidates = Candidacy.where(citizen_id: Citizen.named_like(query).select(:id))
    joins(:election, office: :position).where(
      "positions.title ILIKE :pattern OR elections.name ILIKE :pattern OR races.description ILIKE :pattern OR races.id IN (:candidate_races)",
      pattern: pattern, candidate_races: candidates.select(:race_id)
    )
  }

  delegate :election_date, :year, to: :election
  delegate :current_office_holder, to: :office

  def name
    "#{office.name} - #{year.year}"
  end

  # Approvals for every candidacy across all saved mountains, residents' and visitors' alike.
  def aggregate_votes
    approvals = mountain_ratings.approved.group(:candidacy_id).count
    candidacies.to_h { [ it, approvals.fetch(it.id, 0) ] }
  end

  # What one group's saved mountains add up to, recounted at most once an hour.
  def results_for(group = "resident")
    Rails.cache.fetch([ "race-results-v2", id, group, Time.current.beginning_of_hour.to_i ], expires_in: 1.hour) do
      RaceResults.new(self, group: group).summary
    end
  end

  def mock?
    election.is_mock
  end

  # Which mode strip a voter sees on this race: their own ballot, a pretend vote, a mock, or a replay.
  def mode_for(voter)
    return election.mode unless election.mode == "real"

    voter.resident_of?(self) ? "ballot" : "pretend"
  end

  def counted_as_for(voter)
    voter.resident_of?(self) ? "resident" : "visitor"
  end

  # A replay shows the certified result only once the voter has saved their own mountain.
  def official_results_revealed_to?(voter)
    election.is_historical && voter_race_baselines.exists?(voter: voter)
  end

  def approval_results
    aggregate_votes.sort_by { |candidacy, votes| -votes }
  end

  # The candidacies a voter sees and rates: those the primaries eliminated only if they opted in.
  def candidacies_for(voter)
    voter&.includes_primary_candidates?(self) ? candidacies : candidacies.not_from_primaries
  end

  # The same year's primaries for this office's nominations, such as each party's primary for governor.
  def nomination_races
    Race.joins(:election).where(office: office.nominations, elections: { year_id: election.year_id })
  end

  # Gives everyone still running in this office's primaries a candidacy here, off the ballot unless
  # the data places them on it, so a simulated approval vote can rate those the primary eliminated.
  # Returns the candidacies it added.
  def gather_primary_candidates!
    running = Candidacy.where(race: nomination_races).still_running.order(:id).group_by(&:citizen_id)
    gathered = candidacies.from_primaries.includes(:primary_candidacy).index_by(&:citizen_id)
    gathered.each { |citizen_id, candidacy| candidacy.destroy! unless running.key?(citizen_id) }
    placed = candidacies.pluck(:citizen_id).to_set
    running.each do |citizen_id, primary_candidacies|
      candidacy = gathered[citizen_id]
      candidacy.update!(primary_candidacy: primary_candidacies.first) if candidacy && !primary_candidacies.include?(candidacy.primary_candidacy)
    end
    running.except(*placed).map do |_citizen_id, primary_candidacies|
      candidacies.create!(citizen_id: primary_candidacies.first.citizen_id, primary_candidacy: primary_candidacies.first, status: "active", participation: "off_ballot")
    end
  end

  # Every general with nominations, plus any that still holds candidacies from primaries since removed.
  def self.gather_primary_candidates!
    where(office_id: Office.nominations.select(:nominee_for_office_id)).or(where(id: Candidacy.from_primaries.select(:race_id)))
      .where.not(election_id: Election.primaries.select(:id))
      .includes(:election, :office).find_each.flat_map(&:gather_primary_candidates!)
  end

  def approval_winner
    results = aggregate_votes
    return nil if results.empty? || results.values.all?(&:zero?)

    results.max_by { |candidacy, votes| votes }&.first
  end

  def result_for(candidacy)
    aggregate_votes[candidacy] || 0
  end

  def results_summary
    results = aggregate_votes
    total_possible_voters = voter_race_baselines.count
    total_votes_cast = results.values.sum

    {
      total_candidacies: candidacies.count,
      total_registered_voters: total_possible_voters,
      total_approval_votes: total_votes_cast,
      average_approvals_per_voter: total_possible_voters.zero? ? 0 : (total_votes_cast.to_f / total_possible_voters).round(2),
      winner: approval_winner&.citizen&.name,
      winning_vote_count: results.values.max || 0
    }
  end

  private

  # One election day can decide offices across its jurisdiction, such as a state primary's district nominations.
  def office_matches_election_jurisdiction
    if office && election && !election.jurisdiction.contains?(office.jurisdiction)
      errors.add(:office, "must be within the election's jurisdiction")
    end
  end
end

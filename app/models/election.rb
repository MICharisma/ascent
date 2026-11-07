class Election < ApplicationRecord
  # Elections that decide nominations rather than offices.
  PRIMARY_KINDS = %w[primary primary_runoff].freeze

  # Statuses in which voters can still build mountains for the election's races.
  OPEN_STATUSES = %w[upcoming active].freeze

  # The tabs of the elections list, and the kinds its chips filter by.
  LISTING_TABS = %w[upcoming past mock historical all].freeze
  KIND_GROUPS = { "general" => %w[general], "primary" => PRIMARY_KINDS, "special" => %w[special] }.freeze

  include Engageable

  belongs_to :jurisdiction
  belongs_to :year
  # Whoever made a mock election; real and historical elections come from official sources.
  belongs_to :creator, class_name: "Voter", optional: true
  has_many :races, dependent: :destroy
  has_many :offices, through: :races
  has_many :candidacies, through: :races
  has_many :candidates, through: :candidacies, source: :citizen

  validates :name, :election_date, presence: true
  validates :status, presence: true, inclusion: { in: %w[upcoming active completed cancelled] }
  validates :is_mock, :is_historical, inclusion: { in: [ true, false ] }
  validate :early_voting_dates_are_ordered
  validate :race_offices_match_jurisdiction, if: :will_save_change_to_jurisdiction_id?

  scope :upcoming, -> { where(status: "upcoming") }
  scope :active, -> { where(status: "active") }
  scope :completed, -> { where(status: "completed") }
  scope :mock, -> { where(is_mock: true) }
  scope :historical, -> { where(is_historical: true) }
  scope :real, -> { where(is_mock: false, is_historical: false) }
  scope :open_to_rating, -> { where(status: OPEN_STATUSES) }
  scope :created_by, ->(voter) { where(creator: voter) }
  scope :in_jurisdictions, ->(jurisdictions) { where(jurisdiction_id: jurisdictions.select(:id)) }
  scope :finished, -> { where(status: %w[completed cancelled]) }
  scope :of_kind, ->(group) { where(kind: KIND_GROUPS.fetch(group)) }
  scope :soonest_first, -> { order(:election_date, :name) }
  scope :latest_first, -> { order(election_date: :desc, name: :asc) }
  scope :matching, ->(query) {
    where("elections.name ILIKE ?", "%#{sanitize_sql_like(query.strip)}%").or(where(jurisdiction_id: Jurisdiction.named_like(query).select(:id)))
  }
  scope :held_before, ->(date) { where(election_date: ...date) }
  scope :held_after, ->(date) { where("elections.election_date > ?", date) }
  scope :recent, -> { order(election_date: :desc) }
  scope :primaries, -> { where(kind: PRIMARY_KINDS) }
  scope :with_full_details, -> { includes(:jurisdiction, races: [ :office, :candidates, :candidacies ]) }
  scope :with_candidacy_details, -> { includes(races: { candidacies: [ :citizen, :ratings ] }) }

  # Which kind of election this is, for the mode strip: a real one, a mock one, or a historical replay.
  def mode
    if is_mock then "mock"
    elsif is_historical then "historical"
    else "real"
    end
  end

  # Removes a mock election with the inactive offices and fictional candidates made for it.
  def destroy_mock!
    transaction do
      invented_offices = offices.to_a
      invented_citizens = candidates.fictional.to_a
      destroy!
      invented_offices.each(&:destroy!)
      invented_citizens.each(&:destroy!)
    end
  end

  # One tab of the elections list: open real elections soonest first, finished ones latest first,
  # mock and historical ones apart, or everything.
  def self.listing(tab)
    case tab
    when "upcoming" then real.open_to_rating.soonest_first
    when "past" then real.finished.latest_first
    when "mock" then mock.latest_first
    when "historical" then historical.latest_first
    else latest_first
    end
  end

  def open_to_rating?
    OPEN_STATUSES.include?(status)
  end

  # The races grouped into contests the way a printed ballot reads: federal offices first, then by how
  # many candidates are running. Each contest is [[level, position title], races].
  def contests
    races.includes(candidacies: :citizen, office: [ :position, { jurisdiction: :jurisdictionable } ])
      .group_by { [ it.office.jurisdiction.ballot_level, it.office.position.title ] }
      .sort_by { |(level, title), contest_races| [ -Jurisdiction::BALLOT_LEVELS.index(level), -contest_races.sum { it.candidacies.size }, title ] }
  end

  def mountain_count
    VoterRaceBaseline.where(race: races).count
  end

  def participant_count
    VoterRaceBaseline.where(race: races).distinct.count(:voter_id)
  end

  def previous_in_jurisdiction
    Election.where(jurisdiction: jurisdiction).held_before(election_date).recent.first
  end

  def next_in_jurisdiction
    Election.where(jurisdiction: jurisdiction).held_after(election_date).order(:election_date).first
  end

  def days_until
    (election_date - Date.current).to_i
  end

  private

  def race_offices_match_jurisdiction
    if jurisdiction && races.joins(:office).where.not(offices: { jurisdiction_id: jurisdiction.self_and_descendants.select(:id) }).exists?
      errors.add(:jurisdiction, "must contain the offices of its races")
    end
  end

  def early_voting_dates_are_ordered
    if early_voting_starts_on && early_voting_ends_on && early_voting_starts_on > early_voting_ends_on
      errors.add(:early_voting_ends_on, "must be on or after early voting starts")
    end
    return unless election_date

    [ :early_voting_starts_on, :early_voting_ends_on ].each do |attribute|
      if self[attribute] && self[attribute] > election_date
        errors.add(attribute, "must be on or before election day")
      end
    end
  end
end

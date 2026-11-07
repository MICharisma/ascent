class Rating < ApplicationRecord
  belongs_to :voter
  belongs_to :candidacy

  validates :rating, presence: true, inclusion: { in: 0..500 }
  validates :voter_id, uniqueness: { scope: :candidacy_id, message: "can only rate each candidacy once" }

  before_update :archive_previous_rating

  scope :above_baseline, ->(baseline) { where("rating > ?", baseline) }
  scope :below_baseline, ->(baseline) { where("rating <= ?", baseline) }
  scope :for_race, ->(race) { joins(:candidacy).where(candidacies: { race: race }) }
  scope :for_election, ->(election) { joins(candidacy: :race).where(races: { election: election }) }
  scope :for_voter_in_election, ->(voter, election) {
    joins(candidacy: :race).where(voter: voter, races: { election: election })
  }
  scope :with_election_context, -> {
    joins(candidacy: { race: [ :election, { office: :position } ] })
  }

  def approved?(baseline = nil)
    baseline ||= voter_baseline_for_race
    return false unless baseline
    rating > baseline
  end

  def name
    "#{voter.name} rating for #{candidacy.citizen.name}"
  end

  def rating_percentage
    (rating / 500.0 * 100).round(1)
  end

  def voter_baseline_for_race
    voter.voter_race_baselines.find_by(race: candidacy.race)&.baseline
  end

  private

  def archive_previous_rating
    if rating_changed?
      RatingArchive.create!(
        voter: voter,
        candidacy: candidacy,
        rating: rating_was || rating,
        archived_at: Time.current,
        reason: "Updated rating: #{rating_was} → #{rating}"
      )
    end
  end
end

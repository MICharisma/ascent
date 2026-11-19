# A voter's unsaved changes to one race's mountain. Ratings are keyed by candidacy id; a null rating
# removes the saved one when the draft is saved, and a null baseline leaves the saved baseline alone.
class MountainDraft < ApplicationRecord
  belongs_to :voter
  belongs_to :race

  validates :race_id, uniqueness: { scope: :voter_id }
  validates :baseline, inclusion: { in: 0..500 }, allow_nil: true
  validate :ratings_are_in_range
  validate :ratings_are_for_the_voters_candidacies

  scope :for_voter, ->(voter) { where(voter: voter) }

  # Ratings by candidacy id, nil where the draft removes a saved rating.
  def ratings_by_candidacy
    ratings.transform_keys(&:to_s)
  end

  # Folds further edits into the draft: blank ratings become removals, values clamp to 0..500.
  def revise(ratings: {}, baseline: nil)
    self.ratings = self.ratings.merge(ratings.to_h { |candidacy_id, value| [ candidacy_id.to_s, value.presence&.to_i&.clamp(0, 500) ] })
    self.baseline = baseline.to_i.clamp(0, 500) if baseline.present?
    self
  end

  private

  def ratings_are_in_range
    errors.add(:ratings, "must be between 0 and 500") unless ratings.values.compact.all? { it.is_a?(Integer) && it.between?(0, 500) }
  end

  def ratings_are_for_the_voters_candidacies
    return unless voter && race

    unknown = ratings_by_candidacy.keys - race.candidacies_for(voter).ids
    errors.add(:ratings, "include candidates not on this mountain") if unknown.any?
  end
end

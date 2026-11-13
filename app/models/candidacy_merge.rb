class CandidacyMerge < ApplicationRecord
  belongs_to :candidacy

  validates :old_candidacy_id, uniqueness: true
  validates :performed_by, presence: true
end

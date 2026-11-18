class CitizenMerge < ApplicationRecord
  belongs_to :citizen

  validates :old_citizen_id, uniqueness: true
  validates :performed_by, presence: true
end

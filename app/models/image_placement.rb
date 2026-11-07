class ImagePlacement < ApplicationRecord
  SUBJECT_TYPES = %w[Citizen Candidacy].freeze

  belongs_to :image
  belongs_to :subject, polymorphic: true

  accepts_nested_attributes_for :image, reject_if: :all_blank

  validates :subject_type, inclusion: { in: SUBJECT_TYPES }
  validates :image_id, uniqueness: { scope: %i[subject_type subject_id] }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end

# One voter's current score for one quality of a citizen or policy.
class DimensionRating < ApplicationRecord
  belongs_to :voter
  belongs_to :rated, polymorphic: true

  validates :value, presence: true
  validates :dimension_key, uniqueness: { scope: %i[voter_id rated_type rated_id] }
  validate :dimension_exists_for_rated
  validate :value_on_dimension_scale, if: :dimension

  before_validation :adopt_dimension_version, if: :dimension
  after_create { record_revision "rate" }
  after_update { record_revision "change" if saved_change_to_value? }
  before_destroy { record_revision "clear" unless destroyed_by_association }

  def dimension
    rated&.class&.rating_dimension_for dimension_key
  end

  private

  def adopt_dimension_version
    self.dimension_version = dimension.version
  end

  def dimension_exists_for_rated
    errors.add :dimension_key, "isn't a quality voters rate here" unless dimension
  end

  def value_on_dimension_scale
    dimension.validate_score! value
  rescue ArgumentError
    errors.add :value, "must be a whole number from #{dimension.minimum} to #{dimension.maximum}"
  end

  def record_revision(event)
    DimensionRatingRevision.create! voter: voter, rated_type: rated_type, rated_id: rated_id, dimension_key: dimension_key,
      event: event, value: value, definition: dimension.to_h
  end
end

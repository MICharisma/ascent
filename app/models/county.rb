class County < ApplicationRecord
  include JurisdictionOwner
  include AdoptsRizzCode

  belongs_to :state
  has_many :municipalities, dependent: :nullify

  validates :name, presence: true
  normalizes :fips, with: -> { it.presence }
  validates :fips, format: { with: /\A[0-9]{5}\z/ }, allow_nil: true
  validate :fips_matches_census_geoid

  scope :in_state, ->(state) { where(state: state) }

  private

  def fips_matches_census_geoid
    if fips && jurisdiction&.census_geoid && fips != jurisdiction.census_geoid
      errors.add(:fips, "must match the jurisdiction's Census GEOID")
    end
  end
end

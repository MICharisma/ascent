class Municipality < ApplicationRecord
  include JurisdictionOwner
  include AdoptsRizzCode
  include Engageable

  belongs_to :state
  belongs_to :county, optional: true
  # The town this one sits inside, as Brooklyn sits inside New York City; its jurisdiction nests there.
  belongs_to :parent_municipality, class_name: "Municipality", optional: true
  has_many :inner_municipalities, class_name: "Municipality", foreign_key: :parent_municipality_id,
    inverse_of: :parent_municipality, dependent: :restrict_with_error

  validates :name, presence: true
  validate :county_matches_state
  validate :parent_municipality_matches_state

  scope :in_state, ->(state) { where(state: state) if state.present? }
  scope :with_office_data, -> { includes(:state, jurisdiction: :offices) }

  # The county, unless it is the city itself, as with Virginia's independent cities.
  def distinct_county
    county unless county&.name&.start_with?(name)
  end

  # The jurisdictions decided here: the city and the wards and districts within it.
  def local_jurisdictions
    jurisdiction ? Jurisdiction.and_their_descendants(jurisdiction) : Jurisdiction.none
  end

  # The open real races every resident also votes in, decided by the city, county, state or country
  # above. A town inside a city has its county beside it rather than above it.
  def open_races_above
    return Race.none unless jurisdiction

    above = [ jurisdiction.parent || jurisdiction, county&.jurisdiction ].compact
    Race.real.open_to_rating.in_jurisdictions(Jurisdiction.and_their_ancestors(above))
      .where.not(id: open_local_races.select(:id))
  end

  # The other municipalities in the same county, for moving along the map.
  def neighbors
    county ? county.municipalities.where.not(id: id).order(:name) : Municipality.none
  end

  private

  def county_matches_state
    errors.add(:county, "must belong to the same state") if county && county.state != state
  end

  def parent_municipality_matches_state
    errors.add(:parent_municipality, "must belong to the same state") if parent_municipality && parent_municipality.state != state
  end
end

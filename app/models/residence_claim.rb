# A voter saying where they live, or used to live: a town (or the county, outside any town) and the
# areas it sits in, with dates for a past residence. The areas are its county, which a city spanning
# several can't settle alone, and its House, state senate and state assembly districts.
#
# A location is used once, never kept: it finds the smallest town and the county and district of each
# chamber whose boundaries cover it. A street address becomes a location through the Census geocoder
# and is dropped as soon as it has one. A searched town fills in each area it lies wholly inside; where the
# town is split, the voter picks from the areas it overlaps, or from the state's when no boundaries are
# mapped.
class ResidenceClaim
  include ActiveModel::Model
  include ActiveModel::Attributes

  AREAS = Residence::AREA_SLOTS.keys.freeze
  AREA_LABELS = { "county" => "County", "congressional" => "U.S. House district", "state_senate" => "State senate district",
                  "state_house" => "State assembly district" }.freeze

  attribute :address, :string
  attribute :latitude, :float
  attribute :longitude, :float
  attribute :jurisdiction_id, :string
  attribute :county_id, :string
  attribute :congressional_district_id, :string
  attribute :state_senate_district_id, :string
  attribute :state_house_district_id, :string
  attribute :started_on, :date
  attribute :ended_on, :date
  attribute :past, :boolean, default: false
  # Whether the voter moved here, ending the other places they live, or lives here as well.
  attribute :moving, :boolean, default: true
  attr_accessor :voter
  # The address as the Census matched it, for the voter to check; never saved.
  attr_reader :matched_address

  validates :latitude, numericality: { in: -90..90 }, if: :from_location?
  validates :longitude, numericality: { in: -180..180 }, if: :from_location?
  validates :started_on, :ended_on, presence: true, if: :past
  validate :town_found
  validate :dates_in_order

  def initialize(...)
    super
    locate_address if address.present? && !from_location?
  end

  def from_location?
    latitude.present? && longitude.present?
  end

  def from_address?
    matched_address.present?
  end

  # The jurisdictions whose boundaries cover the location, today.
  def covering
    @covering ||= from_location? ? Jurisdiction.covering(longitude, latitude).includes(:jurisdictionable).to_a : []
  end

  # The town: the smallest one the location falls in, else its county, else its state; or the one chosen.
  def town
    @town ||= from_location? ? smallest_covering : Jurisdiction.find_by(id: jurisdiction_id)
  end

  # The county, or a chamber's district: the voter's pick, else the one the location falls in, else the
  # only one the town overlaps.
  def area(kind)
    picked(kind) || covering.find { of_kind?(it, kind) } || sole_overlap(kind)
  end

  def areas
    AREAS.index_with { area(it) }
  end

  # The areas to pick from when the town alone doesn't settle one.
  def area_choices(kind)
    overlapping(kind).presence || state_areas(kind)
  end

  def needs_pick?(kind)
    area(kind).nil? && area_choices(kind).any?
  end

  def ballot_jurisdictions
    Jurisdiction.and_their_ancestors(Jurisdiction.where(id: [ town, *areas.values ].compact.map(&:id)))
  end

  def open_races
    Race.real.open_to_rating.in_jurisdictions(ballot_jurisdictions)
  end

  # Open races by ballot level, city first, for showing what the voter would see.
  def open_race_counts
    open_races.includes(office: :jurisdiction).group_by { it.office.jurisdiction.ballot_level }.transform_values(&:size)
      .sort_by { |level, _| Jurisdiction::BALLOT_LEVELS.index(level) }.to_h
  end

  def save!
    validate!
    if past
      voter.add_past_residence!(town, started_on: started_on, ended_on: ended_on, areas: areas)
    else
      voter.claim_residence!(town, areas: areas, moving: moving)
    end
  end

  private

  def smallest_covering
    %w[Municipality County State].lazy.filter_map { |type| smallest(covering.select { it.jurisdictionable_type == type }) }.first
  end

  def smallest(jurisdictions)
    return jurisdictions.first if jurisdictions.size < 2

    JurisdictionBoundary.effective_on(Date.current).where(jurisdiction: jurisdictions).order(Arel.sql("ST_Area(geometry)")).first&.jurisdiction
  end

  def of_kind(kind)
    kind == "county" ? Jurisdiction.where(jurisdictionable_type: "County") : Jurisdiction.districts_of_chamber(kind)
  end

  def of_kind?(jurisdiction, kind)
    kind == "county" ? jurisdiction.jurisdictionable_type == "County" : jurisdiction.jurisdictionable.try(:chamber) == kind
  end

  def picked(kind)
    id = public_send("#{Residence::AREA_SLOTS.fetch(kind)}_id")
    of_kind(kind).find_by(id: id) if id
  end

  def overlapping(kind)
    @overlapping ||= {}
    @overlapping[kind] ||= town ? of_kind(kind).overlapping(town).includes(:jurisdictionable).to_a : []
  end

  def sole_overlap(kind)
    choices = overlapping(kind)
    choices.first if choices.one?
  end

  def state_areas(kind)
    state = town&.self_and_ancestors&.find_by(jurisdictionable_type: "State")
    state ? of_kind(kind).where(parent: state).includes(:jurisdictionable).sort_by { it.name.to_s }.to_a : []
  end

  # Turns the address into a point, then forgets the address.
  def locate_address
    match = CensusGeocoder.locate(address)
    @address_problem = :unmatched unless match
    self.latitude, self.longitude, @matched_address = match&.latitude, match&.longitude, match&.matched_address
  rescue CensusGeocoder::Unavailable
    @address_problem = :unavailable
  ensure
    self.address = nil
  end

  def town_found
    errors.add(:base, unplaced_message) unless town
  end

  def unplaced_message
    case @address_problem
    when :unmatched then "We couldn't find that address. Check the street number, city and state, or search for your city or town instead."
    when :unavailable then "The address lookup isn't answering right now. Use your location or search for your city or town instead."
    else "We couldn't place that location yet. Search for your city or town instead."
    end
  end

  def dates_in_order
    errors.add(:ended_on, "must be on or after the date you moved in") if started_on && ended_on && ended_on < started_on
  end
end

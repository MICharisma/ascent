# Finds Ascent's countries, states, counties and incorporated places in Rizz's place catalog and adopts
# their MIC-RZZ codes (MIC-RZZ-CTRY-US, MIC-RZZ-DIV-US-IN, MIC-RZZ-SUBDIV-US-IN-ADAMS,
# MIC-RZZ-LOC-US-IN-ANDERSON), keeping each record's Ascent code as an alias. Seeding never calls Rizz;
# this runs as its own step (bin/rails rizz:sync_places).
#
# Every match is by identifier, never by name: countries and states by ISO code, counties by FIPS, and a
# municipality by the Census place GEOID its jurisdiction carries after a TIGER boundary import. A
# municipality without one, such as a township or a ward, keeps its Ascent code.
#
# Each record takes the code at its own tier. Rizz holds a county and a city on the same land (Richmond
# city, Virginia) as one place whose lower tier is an alias, so the county takes
# MIC-RZZ-SUBDIV-US-VA-RICHMOND_CITY and the municipality MIC-RZZ-LOC-US-VA-RICHMOND. A Rizz code another
# Ascent record already holds is reported as a conflict.
#
# Needs the rizz-client gem, RIZZ_ENDPOINT and RIZZ_API_TOKEN.
class RizzPlaceSync
  Outcome = Data.define :record, :state, :code, :detail
  # Ascent country codes that differ from ISO 3166-1.
  ISO_COUNTRIES = { "UK" => "GB" }.freeze
  INCORPORATED_PLACE = "G4110".freeze

  def self.client
    require "rizz-client"
    Rizz::Client.new endpoint: ENV.fetch("RIZZ_ENDPOINT"), token: ENV.fetch("RIZZ_API_TOKEN")
  end

  def initialize(client: self.class.client)
    @client = client
  end

  def call
    Country.order(:id).map { |country| sync(country) { resolve "iso3166-1:alpha2", iso_country(country), "CTRY" } } +
      State.includes(:country).order(:id).map { |state| sync(state) { resolve "iso3166-2", iso_state(state), "DIV" } } +
      County.order(:id).map { |county| sync(county) { county.fips ? resolve("census.tiger:county", county.fips, "SUBDIV") : [ nil, "no FIPS code" ] } } +
      Municipality.includes(:jurisdiction).order(:id).map { |municipality| sync(municipality) { resolve_municipality municipality } }
  end

  private

  attr_reader :client

  # A Rizz place code never changes, so an adopted record needs no request.
  def sync(record)
    return Outcome.new(record, "unchanged", record.entity_code, nil) if record.rizz_code?

    code, detail = yield
    return Outcome.new(record, "missing", nil, detail) unless code

    holder = holder_of code, record
    return Outcome.new(record, "conflict", code, "#{holder.class.name} #{holder.id} holds #{code}") if holder

    record.adopt_rizz_code! code
    Outcome.new record, "adopted", code, nil
  rescue Rizz::Unavailable, Rizz::Error => error
    Outcome.new record, "failed", nil, "#{error.class}: #{error.message}".truncate(255)
  end

  def resolve_municipality(municipality)
    jurisdiction = municipality.jurisdiction
    return [ nil, "not an incorporated Census place" ] unless jurisdiction&.census_class == INCORPORATED_PLACE

    resolve "census.tiger:place", jurisdiction.census_geoid, "LOC"
  end

  def resolve(namespace, external_id, tier)
    binding = client.resolve_place namespace: namespace, external_id: external_id
    code_at client.entity(binding.fetch("entity_id")), tier
  rescue Rizz::Error => error
    raise unless error.status == 404

    [ nil, "no Rizz place for #{namespace} #{external_id}" ]
  end

  # Another Ascent record, of any kind, that already holds this Rizz code.
  def holder_of(code, record)
    binding = EntityCode.find_by namespace: AdoptsRizzCode::RIZZ_NAMESPACE, catalog: AdoptsRizzCode::RIZZ_CATALOG,
      code: code.delete_prefix(AdoptsRizzCode::RIZZ_PREFIX)
    holder = binding&.record || record.class.find_by(entity_code: code)
    holder unless holder == record
  end

  # The place's own code at that tier, or its alias there for the same land.
  def code_at(place, tier)
    return place.fetch("qualified_code") if place["place_tier"].nil? || place["place_tier"] == tier

    alias_code = place.fetch("alias_codes", []).find { it.start_with? "#{tier}-" }
    alias_code ? "#{AdoptsRizzCode::RIZZ_PREFIX}#{alias_code}" : place.fetch("qualified_code")
  end

  def iso_country(country)
    ISO_COUNTRIES.fetch country.code, country.code
  end

  def iso_state(state)
    "#{iso_country state.country}-#{state.code}"
  end
end

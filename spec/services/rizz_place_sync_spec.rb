require "rails_helper"

RSpec.describe RizzPlaceSync do
  let(:client) { double "Rizz client" }
  let(:service) { described_class.new client: client }
  let!(:united_states) { create :country, name: "United States", code: "US", entity_code: "COUNTRY-USA" }
  let!(:united_kingdom) { create :country, name: "United Kingdom", code: "UK" }
  let!(:virginia) { create :state, name: "Virginia", code: "VA", country: united_states, entity_code: "STATE-USA-VA" }
  let!(:richmond_county) { create :county, name: "Richmond County", fips: "51159", state: virginia, entity_code: "COUNTY-USA-VA-RICHMOND" }
  let!(:richmond_city_county) { create :county, name: "Richmond city", fips: "51760", state: virginia, entity_code: "COUNTY-USA-VA-RICHMOND_CITY" }
  let!(:richmond_city) { create :municipality, name: "Richmond", state: virginia, county: richmond_city_county, entity_code: "MUNICIPALITY-USA-VA-RICHMOND" }
  let!(:alexandria) { create :municipality, name: "Alexandria", state: virginia, entity_code: "MUNICIPALITY-USA-VA-ALEXANDRIA" }
  let!(:township) { create :municipality, name: "Brandon", state: virginia, entity_code: "MUNICIPALITY-USA-VA-BRANDON_TOWNSHIP" }
  let(:places) do
    {
      "iso3166-1:alpha2 US" => "CTRY-US", "iso3166-1:alpha2 GB" => "CTRY-GB", "iso3166-2 US-VA" => "DIV-US-VA",
      "census.tiger:county 51159" => "SUBDIV-US-VA-RICHMOND_COUNTY", "census.tiger:county 51760" => "SUBDIV-US-VA-RICHMOND_CITY",
      "census.tiger:place 5167000" => "SUBDIV-US-VA-RICHMOND_CITY", "census.tiger:place 5101000" => "LOC-US-VA-ALEXANDRIA"
    }
  end

  before do
    stub_const "Rizz::Error", Class.new(StandardError) { attr_accessor :status }
    stub_const "Rizz::Unavailable", Class.new(StandardError)
    allow(client).to receive(:resolve_place) do |namespace:, external_id:|
      code = places.fetch("#{namespace} #{external_id}") { raise Rizz::Error.new.tap { it.status = 404 } }
      { "entity_id" => code }
    end
    allow(client).to receive(:entity) do |code|
      tier = code.split("-").first
      aliases = code == "SUBDIV-US-VA-RICHMOND_CITY" ? [ "LOC-US-VA-RICHMOND" ] : []
      { "qualified_code" => "MIC-RZZ-#{code}", "place_tier" => tier, "alias_codes" => aliases }
    end
    create :jurisdiction, jurisdictionable: richmond_city, census_class: "G4110", census_geoid: "5167000"
    create :jurisdiction, jurisdictionable: alexandria, census_class: "G4110", census_geoid: "5101000"
    create :jurisdiction, jurisdictionable: township, census_class: "G4040", census_geoid: "5103391234"
  end

  it "adopts Rizz codes by ISO code, FIPS and Census place GEOID, keeping Ascent's codes as aliases" do
    outcomes = service.call.index_by(&:record)

    expect(outcomes.transform_values(&:state)).to include(united_states => "adopted", united_kingdom => "adopted", virginia => "adopted",
      richmond_county => "adopted", richmond_city_county => "adopted", alexandria => "adopted")
    expect(united_kingdom.reload.entity_code).to eq "MIC-RZZ-CTRY-GB"
    expect(richmond_county.reload.entity_code).to eq "MIC-RZZ-SUBDIV-US-VA-RICHMOND_COUNTY"
    expect(alexandria.reload.entity_code).to eq "MIC-RZZ-LOC-US-VA-ALEXANDRIA"
    expect(EntityCode.find_by!(catalog: "ASC", code: "COUNTRY-USA")).to have_attributes canonical_code: "MIC-RZZ-CTRY-US", record: united_states
    expect(EntityCode.find_by!(catalog: "RZZ", code: "DIV-US-VA").record).to eq virginia
    expect(outcomes.fetch(township)).to have_attributes state: "missing", detail: "not an incorporated Census place"
    expect(outcomes.fetch(richmond_city).state).to eq "adopted"
    expect(richmond_city_county.reload.entity_code).to eq "MIC-RZZ-SUBDIV-US-VA-RICHMOND_CITY"
    expect(richmond_city.reload.entity_code).to eq "MIC-RZZ-LOC-US-VA-RICHMOND"
    expect(service.call.map(&:state).tally).to eq("unchanged" => 7, "missing" => 1)
  end

  it "reports a Rizz code that another Ascent record already holds" do
    other = create :municipality, name: "Richmond", state: virginia, entity_code: "MIC-RZZ-LOC-US-VA-RICHMOND"
    EntityCode.create! namespace: "MIC", catalog: "RZZ", code: "LOC-US-VA-RICHMOND", canonical_code: other.entity_code, record: other

    outcome = service.call.find { it.record == richmond_city }

    expect(outcome).to have_attributes state: "conflict", detail: "Municipality #{other.id} holds MIC-RZZ-LOC-US-VA-RICHMOND"
    expect(richmond_city.reload.entity_code).to eq "MUNICIPALITY-USA-VA-RICHMOND"
  end

  it "reports a place Rizz does not know and leaves its code alone" do
    places.delete "census.tiger:county 51159"

    outcome = service.call.find { it.record == richmond_county }

    expect(outcome).to have_attributes state: "missing", detail: "no Rizz place for census.tiger:county 51159"
    expect(richmond_county.reload.entity_code).to eq "COUNTY-USA-VA-RICHMOND"
  end
end

RSpec.describe Seeds::LibraryImporter, "after places adopt Rizz codes" do
  let(:manifest) { Rails.root.join("spec/fixtures/seed_library/kelles_2024.yml").to_s }

  before { Year.create!(year: 2024, is_even_year: true, is_presidential_year: true) }

  it "replays manifests that name places by their Ascent codes without binding Rizz codes in Ascent's catalog" do
    described_class.new.call [ manifest ]
    new_york = State.find_by! entity_code: "STATE-USA-NY"
    new_york.adopt_rizz_code! "MIC-RZZ-DIV-US-NY"
    Country.find_by!(code: "US").adopt_rizz_code! "MIC-RZZ-CTRY-US"

    replay = described_class.new.call [ manifest ]

    expect(replay[:created]).to be_empty
    expect(new_york.reload.entity_code).to eq "MIC-RZZ-DIV-US-NY"
    expect(EntityCode.where(catalog: "ASC").where("code LIKE 'MIC-%'")).to be_empty
    expect(District.find_by!(entity_code: "DISTRICT-USA-NY-ASSEMBLY-AD_125").jurisdiction.parent.jurisdictionable).to eq new_york
  end
end

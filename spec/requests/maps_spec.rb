require "rails_helper"

RSpec.describe "Map explorer", type: :request do
  around { |example| travel_to(Time.zone.local(2026, 10, 31, 12)) { example.run } }
  let(:country) { create(:country, code: "US", name: "United States") }
  let(:state) { create(:state, :with_jurisdiction, code: "NY", name: "New York", country: country) }
  let(:county) { create(:county, :with_jurisdiction, state: state, name: "Kings County") }
  let(:other_state) { create(:state, :with_jurisdiction, code: "VT", name: "Vermont", country: country) }

  def boundary(jurisdiction, from: Date.new(2024, 1, 1), until_date: nil)
    shape = RGeo::Geos.factory(srid: 4326).parse_wkt(
      "MULTIPOLYGON(((-74 42,-73 42,-73 43,-74 43,-74 42),(-73.8 42.2,-73.8 42.4,-73.6 42.4,-73.6 42.2,-73.8 42.2)),((-72 42,-71 42,-71 43,-72 43,-72 42)))"
    )
    jurisdiction.boundaries.create!(geometry: shape, valid_from: from, valid_until: until_date)
  end

  def payload
    JSON.parse(response.body)
  end

  it "shows public state links and Alaska/Hawaii insets even before geometry is imported" do
    state
    get map_path

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("h1").text).to eq("Explore the United States")
    expect(page.at_css(%(.map-place-links a[href="#{map_path(state_id: state.id)}"])).text).to eq(state.name)
    expect(page.css('[data-boundary-map-target="inset"]').map { it["data-state-code"] }).to eq(%w[AK HI])
    expect(page.at_css('form[aria-label="Choose map area"]')).to be_present
  end

  it "returns only US states, preserving multipart geometry and holes without changing the source" do
    original = boundary(state.jurisdiction)
    stored = original.geometry.as_text
    canada = create(:country, code: "CA", name: "Canada")
    province = create(:state, :with_jurisdiction, code: "ON", country: canada)
    boundary(province.jurisdiction)

    get features_map_path

    expect(response).to have_http_status(:ok)
    expect(payload["type"]).to eq("FeatureCollection")
    expect(payload["features"].size).to eq(1)
    feature = payload["features"].first
    expect(feature["properties"]).to include("name" => state.name, "url" => map_path(state_id: state.id), "boundary_year" => 2024)
    expect(feature["geometry"]["type"]).to eq("MultiPolygon")
    expect(feature["geometry"]["coordinates"].size).to eq(2)
    expect(feature["geometry"]["coordinates"].first.size).to eq(2)
    expect(original.reload.geometry.as_text).to eq(stored)
    expect(payload["vintages"]).to eq([ 2024 ])
    expect(payload["outline"]).to be_nil
  end

  it "loads counties only for the selected state, with a separate state outline" do
    boundary(state.jurisdiction)
    boundary(county.jurisdiction)
    elsewhere = create(:county, :with_jurisdiction, state: other_state)
    boundary(elsewhere.jurisdiction)

    get features_map_path(state_id: state.id, layer: "counties")

    expect(payload["features"].map { it["properties"]["name"] }).to eq([ county.name ])
    expect(payload["features"].first["properties"]["url"]).to eq(county_path(county))
    expect(payload["outline"]["properties"]["name"]).to eq(state.name)
  end

  it "overlays multiple selected layers, reports unavailable ones, and keeps an accessible legend" do
    boundary(state.jurisdiction)
    boundary(county.jurisdiction)
    district = create(:district, name: "NY-10", kind: "congressional district")
    jurisdiction = create(:jurisdiction, jurisdictionable: district, parent: state.jurisdiction)
    boundary(jurisdiction)

    get map_path(state_id: state.id, layers: %w[counties congressional state_senate])
    page = Nokogiri::HTML(response.body)
    expect(page.css('input[name="layers[]"][checked]').map { it["value"] }).to match_array(%w[counties congressional state_senate])
    expect(page.at_css('.map-legend[aria-label="Map layer legend"]')).to be_present
    expect(response.body).to include("Unavailable on this map: State senate districts")

    get features_map_path(state_id: state.id, layers: %w[counties congressional state_senate])
    expect(payload["layers"].map { it["key"] }).to eq(%w[counties congressional state_senate])
    expect(payload["features"].map { it["properties"]["layer"] }.uniq).to match_array(%w[counties congressional])
    expect(payload["unavailable_layers"].map { it["key"] }).to eq([ "state_senate" ])
    expect(payload["legend"].map { it["key"] }).to include("counties", "congressional", "state_senate")
  end


  it "selects each legislative chamber independently and links districts to their own pages" do
    kinds = { "congressional" => "congressional district", "state_senate" => "state senate district", "state_house" => "assembly district" }
    districts = kinds.to_h do |layer, kind|
      district = create(:district, name: "New York #{kind} 10", kind: kind)
      jurisdiction = create(:jurisdiction, jurisdictionable: district, parent: state.jurisdiction)
      boundary(jurisdiction)
      [ layer, district ]
    end
    elsewhere = create(:district, kind: "congressional district")
    boundary(create(:jurisdiction, jurisdictionable: elsewhere, parent: other_state.jurisdiction))

    districts.each do |layer, district|
      get features_map_path(state_id: state.id, layer: layer)

      expect(response).to have_http_status(:ok)
      expect(payload["features"].map { it["properties"]["url"] }).to eq([ district_path(district) ])
    end
  end

  it "uses the effective boundary and excludes future geometry" do
    boundary(state.jurisdiction, from: Date.new(2020, 1, 1), until_date: Date.new(2026, 1, 1))
    boundary(state.jurisdiction, from: Date.new(2026, 1, 1), until_date: Date.new(2030, 1, 1))
    boundary(state.jurisdiction, from: Date.new(2030, 1, 1))

    get features_map_path

    expect(payload["features"].size).to eq(1)
    expect(payload["vintages"]).to eq([ 2026 ])
  end

  it "keeps place links available with missing geometry and shows empty layers clearly" do
    county
    get map_path(state_id: state.id)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css(%(.map-place-links a[href="#{county_path(county)}"]))).to be_present
    expect(page.at_css('a[href="/map"]')).to be_present
    expect(page.at_css('input[name="layers[]"][value="counties"]')["checked"]).to be_present

    get features_map_path(state_id: state.id)
    expect(payload).to include("features" => [], "outline" => nil, "vintages" => [])
    expect(payload["unavailable_layers"].map { it["key"] }).to eq([ "counties" ])

    get map_path(state_id: state.id, layer: "state_senate")
    expect(response.body).to include("No state senate districts are recorded here yet.")
    expect(response.body).to include("Unavailable on this map: State senate districts")
  end


  it "rejects unknown states, non-US states, and unknown layers" do
    canada = create(:country, code: "CA")
    province = create(:state, country: canada)
    [ { state_id: SecureRandom.uuid_v7 }, { state_id: province.id }, { layer: "municipalities" } ].each do |parameters|
      get map_path, params: parameters
      expect(response).to have_http_status(:not_found)
      get features_map_path, params: parameters
      expect(response).to have_http_status(:not_found)
    end
  end

  it "returns only public map metadata without voter or residence data" do
    boundary(state.jurisdiction)
    create(:voter)

    get features_map_path

    expect(payload["features"].first["properties"].keys).to match_array(%w[name url state_code boundary_year])
    expect(response.body).not_to include("email", "voter_id", "residence", "latitude", "longitude")
  end

  it "rejects a state array instead of treating it as a multi-state selection" do
    get features_map_path, params: { state_id: [ state.id, other_state.id ] }

    expect(response).to have_http_status(:bad_request)
  end

  it "caches display GeoJSON and refreshes after a boundary update" do
    allow(Rails.cache).to receive(:fetch).and_call_original
    first_boundary = boundary(state.jurisdiction)

    get features_map_path
    first = response.body
    expect(response.headers["Cache-Control"]).to include("max-age=3600")

    get features_map_path
    expect(response.body).to eq(first)

    first_boundary.update!(valid_until: Date.new(2025, 1, 1))
    boundary(state.jurisdiction, from: Date.new(2025, 1, 1))
    get features_map_path
    expect(JSON.parse(response.body)["vintages"]).to eq([ 2025 ])
  end

  it "refreshes cached geometry after subsecond updates and deletion of a nonlatest boundary" do
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    first_boundary = boundary(state.jurisdiction)
    second_boundary = boundary(other_state.jurisdiction)
    first_boundary.update_columns(updated_at: Time.current + 0.1)
    second_boundary.update_columns(updated_at: Time.current + 0.2)
    get features_map_path
    first_geometry = payload.fetch("features").find { it["id"] == "state-#{state.id}" }.fetch("geometry")
    replacement = RGeo::Geos.factory(srid: 4326).parse_wkt("MULTIPOLYGON(((-74 42,-72 42,-72 44,-74 44,-74 42)))")

    first_boundary.update!(geometry: replacement, updated_at: Time.current + 0.3)
    get features_map_path
    expect(payload.fetch("features").find { it["id"] == "state-#{state.id}" }.fetch("geometry")).not_to eq(first_geometry)

    second_boundary.destroy!
    get features_map_path
    expect(payload.fetch("features").map { it["id"] }).to eq([ "state-#{state.id}" ])
  ensure
    Rails.cache = previous_cache
  end
end

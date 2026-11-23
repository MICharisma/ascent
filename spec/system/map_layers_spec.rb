require "rails_helper"

# Leaflet draws map layers from real layout, so maps stay in Chrome.
RSpec.describe "Map layers", type: :system do
  it "overlays map layers and keeps keyboard selection connected to Ahoy" do
    country = create(:country, code: "US", name: "United States")
    state = create(:state, :with_jurisdiction, code: "NY", name: "New York", country: country)
    county = create(:county, :with_jurisdiction, name: "Kings County", state: state)
    district = create(:district, name: "NY-10", kind: "congressional district")
    district_jurisdiction = create(:jurisdiction, jurisdictionable: district, parent: state.jurisdiction)
    shape = RGeo::Geos.factory(srid: 4326).parse_wkt("MULTIPOLYGON(((-74 42,-73 42,-73 43,-74 43,-74 42)))")
    [ state.jurisdiction, county.jurisdiction, district_jurisdiction ].each do |jurisdiction|
      jurisdiction.boundaries.create!(geometry: shape, valid_from: Date.new(2024, 1, 1))
    end

    visit map_path(state_id: state.id)
    expect(page).to have_content("1 areas mapped.")
    check "Congressional districts"
    expect(page).to have_content("2 areas mapped.")
    expect(page).to have_css(".map-legend", text: "Congressional districts")
    page.execute_script <<~JS
      window.mapEvents = []
      const originalTrack = window.ahoy.track.bind(window.ahoy)
      window.ahoy.track = (name, properties) => {
        window.mapEvents.push({ name, properties })
        return originalTrack(name, properties)
      }
    JS

    find('path[role="link"][aria-label="Kings County (Counties)"]').send_keys(:enter)
    expect(page).to have_current_path(county_path(county))
    expect(page).to have_content("Boundary vintage 2024")
    selected = page.evaluate_script('window.mapEvents.filter(event => event.name === "browse_refined" && event.properties.method === "map_selection")')
    expect(selected.size).to eq(1)
    expect(selected.first.fetch("properties")).to include("destination" => county_path(county), "state_code" => "NY")
  end
end

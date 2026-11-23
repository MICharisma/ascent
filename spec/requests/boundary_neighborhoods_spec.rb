# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Boundary neighborhood context", type: :request do
  around { |example| travel_to(Time.zone.local(2026, 10, 31, 12)) { example.run } }

  let(:country) { create(:country, code: "US") }
  let(:state) { create(:state, :with_jurisdiction, country: country, code: "NY", name: "New York") }

  def add_boundary(jurisdiction, wkt)
    shape = RGeo::Geos.factory(srid: 4326).parse_wkt(wkt)
    jurisdiction.boundaries.create!(geometry: shape, valid_from: Date.new(2024, 1, 1))
  end

  it "renders same-layer neighbor links and overlapping other types on the place page" do
    west = create(:county, :with_jurisdiction, state: state, name: "West County")
    east = create(:county, :with_jurisdiction, state: state, name: "East County")
    district = create(:district, name: "NY-10", kind: "congressional district")
    district_jurisdiction = create(:jurisdiction, jurisdictionable: district, parent: state.jurisdiction)

    add_boundary(west.jurisdiction, "MULTIPOLYGON(((-74 42,-73 42,-73 43,-74 43,-74 42)))")
    add_boundary(east.jurisdiction, "MULTIPOLYGON(((-73 42,-72 42,-72 43,-73 43,-73 42)))")
    add_boundary(district_jurisdiction, "MULTIPOLYGON(((-73.8 42.2,-73.2 42.2,-73.2 42.8,-73.8 42.8,-73.8 42.2)))")

    get county_path(west)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Same-layer neighbors")
    expect(response.body).to include("East County")
    expect(response.body).to include(%(href="#{county_path(east)}"))
    expect(response.body).to include("Overlapping other types")
    expect(response.body).to include("NY-10")
    expect(response.body).to include("is-selected")
    expect(response.body).to include("Adjacent counties")
  end
end

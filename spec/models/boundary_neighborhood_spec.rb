# frozen_string_literal: true

require "rails_helper"

RSpec.describe BoundaryNeighborhood do
  around { |example| travel_to(Time.zone.local(2026, 10, 31, 12)) { example.run } }

  let(:country) { create(:country, code: "US") }
  let(:state) { create(:state, :with_jurisdiction, country: country, code: "NY", name: "New York") }

  def add_boundary(jurisdiction, wkt, from: Date.new(2024, 1, 1))
    shape = RGeo::Geos.factory(srid: 4326).parse_wkt(wkt)
    jurisdiction.boundaries.create!(geometry: shape, valid_from: from)
  end

  it "finds same-layer neighbors that touch, including at a point, and separates overlapping other types" do
    west = create(:county, :with_jurisdiction, state: state, name: "West County")
    east = create(:county, :with_jurisdiction, state: state, name: "East County")
    island = create(:county, :with_jurisdiction, state: state, name: "Island County")
    district = create(:district, name: "NY-10", kind: "congressional district")
    district_jurisdiction = create(:jurisdiction, jurisdictionable: district, parent: state.jurisdiction)

    add_boundary(west.jurisdiction, "MULTIPOLYGON(((-74 42,-73 42,-73 43,-74 43,-74 42)))")
    # Shares the -73 edge with west.
    add_boundary(east.jurisdiction, "MULTIPOLYGON(((-73 42,-72 42,-72 43,-73 43,-73 42)))")
    # Disconnected island: no touch.
    add_boundary(island.jurisdiction, "MULTIPOLYGON(((-70 40,-69 40,-69 41,-70 41,-70 40)))")
    # Overlaps west interior without being the same layer.
    add_boundary(district_jurisdiction, "MULTIPOLYGON(((-73.8 42.2,-73.2 42.2,-73.2 42.8,-73.8 42.8,-73.8 42.2)))")

    neighborhood = described_class.for(west)

    expect(neighborhood.same_layer_neighbors).to contain_exactly(east)
    expect(described_class.for(island).same_layer_neighbors).to eq([])
    expect(neighborhood.overlapping_other_types).to include(district)
    expect(neighborhood.svg).to include("is-selected", "is-neighbor")
  end

  it "treats point-touching corners as adjacent" do
    a = create(:county, :with_jurisdiction, state: state, name: "Corner A")
    b = create(:county, :with_jurisdiction, state: state, name: "Corner B")
    add_boundary(a.jurisdiction, "MULTIPOLYGON(((-74 42,-73 42,-73 43,-74 43,-74 42)))")
    # Touches only at the point (-73, 43).
    add_boundary(b.jurisdiction, "MULTIPOLYGON(((-73 43,-72 43,-72 44,-73 44,-73 43)))")

    expect(described_class.for(a).same_layer_neighbors).to contain_exactly(b)
  end
end

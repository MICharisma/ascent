# frozen_string_literal: true

require "rails_helper"

RSpec.describe BoundaryOutline do
  around { |example| travel_to(Time.zone.local(2026, 10, 31, 12)) { example.run } }

  let(:country) { create(:country, code: "US", name: "United States") }
  let(:state) { create(:state, :with_jurisdiction, code: "NY", name: "New York", country: country) }

  def boundary(jurisdiction, from: Date.new(2024, 1, 1))
    shape = RGeo::Geos.factory(srid: 4326).parse_wkt(
      "MULTIPOLYGON(((-74 42,-73 42,-73 43,-74 43,-74 42),(-73.8 42.2,-73.8 42.4,-73.6 42.4,-73.6 42.2,-73.8 42.2)),((-72 42,-71 42,-71 43,-72 43,-72 42)))"
    )
    jurisdiction.boundaries.create!(geometry: shape, valid_from: from)
  end

  it "builds an SVG path that keeps holes and disconnected parts without changing stored geometry" do
    original = boundary(state.jurisdiction)
    stored = original.geometry.as_text
    outline = described_class.for(state)

    expect(outline).to be_available
    expect(outline.vintage_year).to eq(2024)
    expect(outline).to be_multipart
    expect(outline).to have_holes
    expect(outline.path_data.scan(/\bM\b/).size).to eq(3)
    expect(outline.view_box).to be_present
    expect(outline.svg).to include("viewBox=", 'd="M')
    expect(original.reload.geometry.as_text).to eq(stored)
  end

  it "rasterizes a PNG from the same outline" do
    boundary(state.jurisdiction)
    png = described_class.for(state).png

    expect(png.byteslice(0, 8)).to eq("\x89PNG\r\n\x1A\n".b)
  end

  it "refreshes cached paths when a boundary changes within the same second" do
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    original = boundary(state.jurisdiction)
    original.update_columns(updated_at: Time.current + 0.1)
    first_path = described_class.for(state).path_data
    replacement = RGeo::Geos.factory(srid: 4326).parse_wkt("MULTIPOLYGON(((-74 42,-72 42,-72 44,-74 44,-74 42)))")

    original.update!(geometry: replacement, updated_at: Time.current + 0.2)

    expect(described_class.for(state).path_data).not_to eq(first_path)
  ensure
    Rails.cache = previous_cache
  end

  it "reports missing geometry clearly" do
    outline = described_class.for(state)

    expect(outline).to be_missing
    expect(outline.svg).to be_nil
    expect(outline.png).to be_nil
  end

  it "resolves a race through its office jurisdiction" do
    boundary(state.jurisdiction)
    election = create(:election, :active, jurisdiction: state.jurisdiction)
    office = create(:office, jurisdiction: state.jurisdiction)
    race = create(:race, :active, election: election, office: office)

    expect(described_class.for(race, detail: :compact)).to be_available
  end
end

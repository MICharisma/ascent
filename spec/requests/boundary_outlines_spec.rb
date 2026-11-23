# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Boundary outlines", type: :request do
  around { |example| travel_to(Time.zone.local(2026, 10, 31, 12)) { example.run } }

  let(:country) { create(:country, code: "US", name: "United States") }
  let(:state) { create(:state, :with_jurisdiction, code: "NY", name: "New York", country: country) }
  let(:county) { create(:county, :with_jurisdiction, state: state, name: "Kings County") }

  def boundary(jurisdiction, from: Date.new(2024, 1, 1))
    shape = RGeo::Geos.factory(srid: 4326).parse_wkt(
      "MULTIPOLYGON(((-74 42,-73 42,-73 43,-74 43,-74 42),(-73.8 42.2,-73.8 42.4,-73.6 42.4,-73.6 42.2,-73.8 42.2)),((-72 42,-71 42,-71 43,-72 43,-72 42)))"
    )
    jurisdiction.boundaries.create!(geometry: shape, valid_from: from)
  end

  it "shows an SVG outline and vintage on a place page, and a clear empty state without geometry" do
    get state_path(state)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No boundary is recorded for this place yet.")

    boundary(state.jurisdiction)
    get state_path(state)
    expect(response.body).to include("Boundary vintage 2024")
    expect(response.body).to include("does not verify them for a later election")
    expect(response.body).to include("jurisdiction-outline-shape")
    expect(response.body).to include("Download SVG")
    expect(response.body).to include("Download PNG")
  end

  it "shows compact outlines on race cards when the office jurisdiction has geometry" do
    boundary(county.jurisdiction)
    election = create(:election, :active, jurisdiction: county.jurisdiction)
    office = create(:office, jurisdiction: county.jurisdiction)
    create(:race, :active, election: election, office: office)

    get county_path(county)

    expect(response.body).to include("jurisdiction-outline-compact")
    expect(response.body).to include("Boundary 2024")
  end


  it "serves SVG and PNG downloads without voter data" do
    boundary(state.jurisdiction)
    create(:voter)

    get boundary_outline_path(place_type: "State", place_id: state.id, format: "svg")
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/svg+xml")
    expect(response.body).to include("<svg")
    expect(response.body).not_to include("email", "voter_id", "residence")

    get boundary_outline_path(place_type: "State", place_id: state.id, format: "png")
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.body.byteslice(0, 8)).to eq("\x89PNG\r\n\x1A\n".b)
  end

  it "returns not found when geometry is missing or the place type is unknown" do
    get boundary_outline_path(place_type: "State", place_id: state.id, format: "svg")
    expect(response).to have_http_status(:not_found)

    get "/boundary_outlines/Voter/1.svg"
    expect(response).to have_http_status(:not_found)
  end
end

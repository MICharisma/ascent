require "rails_helper"

# An office's page leads with its next race and its candidates, then the office's other races.
RSpec.describe "Office page", type: :request do
  include_context "Port Merritt ballot"

  let(:office) { office_in(port_merritt, "Mayor") }
  let!(:next_race) { create_race_for(office, :active, name: "Port Merritt Municipal Election") }
  let!(:earlier_race) { create_race_for(office, :completed, name: "Port Merritt Municipal Election 2022", election_date: Date.new(2022, 11, 8)) }
  let!(:okafor) { create(:candidacy, race: next_race, status: "active", citizen: create(:citizen, first_name: "Dana", middle_name: nil, last_name: "Okafor")) }

  it "places the office under its place and leads with its next race" do
    get office_path(office)

    page = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(page.css(".breadcrumb a").map(&:text)).to eq([ "Offices", "Port Merritt" ])
    expect(page.at_css("h1").text).to eq("Mayor")
    expect(page.css("#office-next-race .list-row-title").map(&:text)).to eq([ "Dana Okafor" ])
    expect(page.at_css(".place-actions .pill-button")["href"]).to eq(race_path(next_race))
    expect(page.at_css(".related-list .list-row-title")["href"]).to eq(race_path(earlier_race))
  end

  it "finds offices by title or place, and in a state" do
    elsewhere = create(:office, position: create(:position, title: "Harbor Master"))

    get offices_path, params: { q: "port merritt" }

    expect(response.body).to include(%(id="list_item_office_#{office.id}"))
    expect(response.body).not_to include(%(id="list_item_office_#{elsewhere.id}"))

    get offices_path, params: { q: "harbor" }

    expect(response.body).to include(%(id="list_item_office_#{elsewhere.id}"))

    get offices_path, params: { state_id: state.jurisdictionable.id }

    expect(response.body).to include(%(id="list_item_office_#{office.id}"))
    expect(response.body).not_to include(%(id="list_item_office_#{elsewhere.id}"))
  end

  it "hides offices no longer filled on request" do
    retired = office_in(port_merritt, "Town Crier").tap { it.update!(is_active: false) }

    get offices_path, params: { active: "1" }

    expect(response.body).to include(%(id="list_item_office_#{office.id}"))
    expect(response.body).not_to include(%(id="list_item_office_#{retired.id}"))
  end
end

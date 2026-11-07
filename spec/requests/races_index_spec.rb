require 'rails_helper'

RSpec.describe "Races Index", type: :request do
  let!(:country) { create(:country, name: "United States", code: "US") }
  let!(:state) { create(:state, :with_jurisdiction, name: "California", country: country) }
  let!(:city) { create(:municipality, :with_jurisdiction, name: "Los Angeles", state: state) }
  let!(:mayor_office) { create(:office, position: create(:position, title: "Mayor"), jurisdiction: city.jurisdiction) }
  let!(:governor_office) { create(:office, position: create(:position, :governor), jurisdiction: state.jurisdiction) }
  let!(:mayor_race) { create_race_for(mayor_office, :active) }
  let!(:governor_race) { create_race_for(governor_office, :upcoming) }
  let!(:candidacy) { create(:candidacy, race: mayor_race, citizen: create(:citizen, first_name: "Karen", middle_name: nil, last_name: "Bass")) }

  describe "GET /races" do
    it "lists races with their offices and candidates" do
      get races_path

      expect(response).to have_http_status(200)
      expect(response.body).to include("Mayor of Los Angeles")
      expect(response.body).to include("Governor of California")
    end

    it "combines the selected filters and preserves their values" do
      city.jurisdiction.update!(parent: state.jurisdiction)
      mayor_race.election.update!(year: create(:year, year: 2026), kind: "general")

      get races_path, params: { q: "mayor", state_id: state.id, year: 2026, status: "active", kind: "general" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(id="list_item_race_#{mayor_race.id}"))
      expect(response.body).not_to include(%(id="list_item_race_#{governor_race.id}"))
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('input[name="q"]')["value"]).to eq("mayor")
      expect(page.at_css('select[name="state_id"] option[selected]')["value"]).to eq(state.id.to_s)
      expect(page.at_css('select[name="kind"] option[selected]')["value"]).to eq("general")
    end

    it "searches candidate names without duplicating their race" do
      create(:candidacy, race: mayor_race, citizen: create(:citizen, first_name: "Karen", middle_name: nil, last_name: "Bishop"))

      get races_path, params: { q: "kArEn" }

      expect(response.body.scan(/id="list_item_race_#{mayor_race.id}"/).length).to eq(1)
      expect(response.body).not_to include(%(id="list_item_race_#{governor_race.id}"))
    end

    it "treats wildcard characters as literal search text" do
      get races_path, params: { q: "%_" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No races match")
    end

    it "finds district races nested beneath a state's county jurisdiction" do
      county = create(:county, state: state)
      county_jurisdiction = create(:jurisdiction, jurisdictionable: county, parent: state.jurisdiction)
      district = create(:jurisdiction, :district, parent: county_jurisdiction)
      district_office = create(:office, jurisdiction: district)
      district_race = create_race_for(district_office)
      outside_race = create(:race)

      get races_path, params: { state_id: state.id }

      expect(response.body).to include(%(id="list_item_race_#{district_race.id}"))
      expect(response.body).not_to include(%(id="list_item_race_#{outside_race.id}"))
    end

    it "returns no races for a state that has no jurisdiction" do
      empty_state = create(:state)

      get races_path, params: { state_id: empty_state.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No races match")
    end

    it "keeps filters in pagination links and starts a new filter submission at page one" do
      create_list(:race, Pagy::OPTIONS[:limit], :active)

      get races_path, params: { status: "active" }

      page = Nokogiri::HTML(response.body)
      next_page = page.css('.pagination-nav a[href]').find { it["href"].include?("page=2") }
      expect(next_page["href"]).to include("status=active")
      expect(next_page["data-turbo-frame"]).to eq("races-list")
      expect(next_page["data-turbo-action"]).to eq("advance")
      expect(page.css('.filter-form input[name="page"]')).to be_empty
    end

    it "counts each status in its tab, across the other filters" do
      get races_path, params: { q: "mayor" }

      page = Nokogiri::HTML(response.body)
      tabs = page.css(".listing-tab").to_h { [ it.at_css(".listing-tab-label").text, it.at_css(".listing-tab-count").text ] }
      expect(tabs).to include("All" => "1", "Active" => "1", "Upcoming" => "0")
      expect(page.at_css('.listing-tab[href*="status=active"]')["href"]).to include("q=mayor")
    end

    it "keeps hidden races excluded when searching" do
      voter = create(:voter)
      create(:engagement, voter: voter, engageable: mayor_race, kind: "hide")
      sign_in voter

      get races_path, params: { q: "Karen" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(%(id="list_item_race_#{mayor_race.id}"))
    end
  end

  describe "GET /offices/:office_id/races" do
    it "renders races scoped to one office" do
      get office_races_path(mayor_office)

      expect(response).to have_http_status(200)
      expect(response.body).to include("Mayor of Los Angeles", "Races for Mayor of Los Angeles")
      expect(response.body).not_to include("Governor of California")
    end

    it "retains the office scope when applying or clearing filters" do
      get office_races_path(mayor_office), params: { status: "active" }

      page = Nokogiri::HTML(response.body)
      expect(page.at_css('input[name="office_id"]')["value"]).to eq(mayor_office.id.to_s)
      expect(page.at_css('.filter-form a')["href"]).to eq(races_path(office_id: mayor_office.id))
      expect(response.body).not_to include(%(id="list_item_race_#{governor_race.id}"))
    end
  end

  describe "GET /elections/:election_id/races" do
    it "renders races scoped to one election" do
      get election_races_path(governor_race.election)

      expect(response).to have_http_status(200)
      expect(response.body).to include("Governor of California")
      expect(response.body).not_to include("Mayor of Los Angeles")
    end
  end
end

RSpec.describe "Races Index for a voter who lives somewhere", type: :request do
  include_context "Port Merritt ballot"

  let!(:council_race) { create_race_for(office_in(ward_4, "City Council")) }
  let!(:elsewhere_race) { create_race_for(office_in(ward_2, "City Council")) }

  before { sign_in voter }

  it "marks the races on their ballot and narrows to them on request" do
    get races_path

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#list_item_race_#{council_race.id}")["class"]).to include("is-yours")
    expect(page.at_css("#list_item_race_#{elsewhere_race.id}")["class"]).not_to include("is-yours")

    get races_path, params: { near: "1" }

    expect(response.body).to include(%(id="list_item_race_#{council_race.id}"))
    expect(response.body).not_to include(%(id="list_item_race_#{elsewhere_race.id}"))
  end
end

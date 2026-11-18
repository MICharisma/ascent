require "rails_helper"

# A race's page leads with its candidates and the way to rate them, keeps the candidates the primaries
# eliminated as their own group, and shows the approval tally once mountains are saved.
RSpec.describe "Race page", type: :request do
  include_context "Port Merritt ballot"

  let(:office) { office_in(ward_4, "City Council") }
  let!(:race) { create_race_for(office, :active, name: "Port Merritt Municipal Election") }
  let!(:okafor) { create(:candidacy, race: race, status: "active", citizen: create(:citizen, first_name: "Dana", middle_name: nil, last_name: "Okafor")) }
  let(:harbor_party) { Party.create!(name: "Harbor Party", state: state.jurisdictionable) }
  let(:harbor_nomination) do
    Office.create!(position: Position.create!(title: Position::NOMINEE_TITLE, branch: :legislative), jurisdiction: ward_4,
      nominee_for: office, nominating_organization: harbor_party, nominee_count: 1, is_active: true)
  end
  let!(:pritchett) do
    eliminated = create(:citizen, first_name: "Dwayne", middle_name: nil, last_name: "Pritchett")
    primary = create(:candidacy, citizen: eliminated, race: create_race_for(harbor_nomination, :completed))
    create(:candidacy, race: race, citizen: eliminated, status: "active", participation: "off_ballot", primary_candidacy: primary)
  end

  it "places the race under its election and invites a signed-out visitor to sign in" do
    get race_path(race)

    page = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(page.css(".breadcrumb a").map(&:text)).to eq([ "Elections", "Port Merritt Municipal Election" ])
    expect(page.at_css("h1").text).to eq("City Council")
    expect(response.body).to include("Sign in to build a mountain", "1 candidate on the ballot, and 1 other who ran in the primaries")
  end

  it "lists the ballot's candidates apart from those the primaries eliminated" do
    get race_path(race)

    page = Nokogiri::HTML(response.body)
    expect(page.css("#race-candidates .list-row-title").map(&:text)).to eq([ "Dana Okafor" ])
    expect(page.css(".race-primaries .list-row-title").map(&:text)).to eq([ "Dwayne Pritchett" ])
    expect(page.at_css(".race-primaries .list-row-meta").text).to eq("Off the ballot; ran in the Harbor Party primary")
    expect(page.at_css("#race-candidates .list-row-title")["href"]).to eq(candidacy_path(okafor))
  end

  it "sends a resident to build their own mountain, and a visitor to a pretend vote" do
    sign_in voter
    get race_path(race)

    expect(response.body).to include("Build your mountain", "On your ballot")

    sign_in create(:voter)
    get race_path(race)

    expect(response.body).to include("Pretend vote")
    expect(response.body).not_to include("On your ballot")
  end

  it "shows the approval tally so far once a mountain is saved" do
    get race_path(race)
    expect(response.body).not_to include("Approval so far")

    resident = create(:voter)
    VoterRaceBaseline.create!(voter: resident, race: race, baseline: 250, counted_as: "resident")
    Rating.create!(voter: resident, candidacy: okafor, rating: 400)
    Rails.cache.clear

    get race_path(race)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".approval-bar-name").text).to eq("Dana Okafor")
    expect(page.at_css(".approval-bar-value").text).to eq("100%")
    expect(response.body).to include(race_results_path(race, group: "resident"))
  end

  it "links the office's other races to the office's full list" do
    earlier = create_race_for(office, :completed)

    get race_path(race)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#list_item_race_#{earlier.id}")).to be_present
    expect(page.at_css(".related-list .list-row-title")["href"]).to eq(race_path(earlier))
  end
end

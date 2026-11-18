require "rails_helper"

# A candidacy's page presents a candidate as a citizen running for one seat: their stances by topic,
# endorsements, and the others in the race, with the way to rate them that fits the visitor.
RSpec.describe "Candidacy page", type: :request do
  include_context "Port Merritt ballot"

  let(:race) { create_race_for(office_in(ward_4, "City Council"), :active, name: "Port Merritt Municipal Election") }
  let(:okafor) { create(:citizen, first_name: "Dana", middle_name: nil, last_name: "Okafor") }
  let!(:candidacy) do
    create(:candidacy, race: race, citizen: okafor, status: "active", party_label: "Harbor Party",
      platform_summary: "Rebuild the ferry pier and keep the library open on Sundays.")
  end
  let!(:rival) { create(:candidacy, race: race, status: "active", citizen: create(:citizen, first_name: "Theo", middle_name: nil, last_name: "Lindqvist")) }

  it "places the candidacy under its race and leads with the candidate" do
    get candidacy_path(candidacy)

    page = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(page.css(".breadcrumb a").map(&:text)).to eq([ "Elections", "Port Merritt Municipal Election", "City Council" ])
    expect(page.at_css("h1").text).to eq("Dana Okafor")
    expect(page.at_css(".page-header-chips").text).to include("Harbor Party")
    expect(response.body).to include("Rebuild the ferry pier", "Sign in to rate them")
  end

  it "groups stances by topic and links each to its approach" do
    transit = create(:topic, title: "Transportation")
    housing = create(:topic, title: "Housing")
    ferries = create(:approach, title: "Expand ferry service", issue: create(:issue, title: "Getting downtown", topic: transit))
    rentals = create(:approach, title: "Cap short-term rentals", issue: create(:issue, title: "Rents", topic: housing))
    create(:stance, candidacy: candidacy, approach: ferries, priority_level: "high")
    create(:stance, candidacy: candidacy, approach: rentals, priority_level: "medium")

    get candidacy_path(candidacy)

    page = Nokogiri::HTML(response.body)
    expect(page.css(".stance-group-title").map(&:text)).to eq([ "Housing", "Transportation" ])
    expect(page.css(".stance-group .list-row-title").map(&:text)).to eq([ "Cap short-term rentals", "Expand ferry service" ])
    expect(response.body).to include("On Getting downtown")
  end

  it "explains stances when there are none, and hides empty endorsements" do
    get candidacy_path(candidacy)

    expect(response.body).to include("No stances are recorded yet.")
    expect(Nokogiri::HTML(response.body).css(".place-main h2").map(&:text)).not_to include("Endorsements")
  end

  it "lists current endorsements, strongest first" do
    create(:endorsement, candidacy: candidacy, endorser: create(:organization, name: "Harbor Teachers"), strength: 3)
    create(:endorsement, candidacy: candidacy, endorser: create(:organization, name: "Port Merritt Gazette"), strength: 5)
    create(:endorsement, candidacy: candidacy, endorser: create(:organization, name: "Dockworkers Local 9"), withdrawn_on: Date.new(2026, 10, 1))

    get candidacy_path(candidacy)

    page = Nokogiri::HTML(response.body)
    expect(page.css(".endorsement-name").map(&:text)).to eq([ "Port Merritt Gazette", "Harbor Teachers" ])
  end

  it "lists the others in the race, and offers a signed-in voter their mountain" do
    sign_in voter

    get candidacy_path(candidacy)

    page = Nokogiri::HTML(response.body)
    expect(page.css(".related-list .list-row-title").map(&:text)).to eq([ "Theo Lindqvist" ])
    expect(response.body).to include("Rate them on your mountain", edit_mountain_path(race))
  end
end

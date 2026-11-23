require "rails_helper"

# A city's page leads with the action that fits the visitor, shows only the races decided there (folding
# the rest into counts), and can be bookmarked like any race or candidate.
RSpec.describe "Municipality page", type: :request do
  include_context "Port Merritt ballot"

  let(:city) { port_merritt.jurisdictionable }
  let!(:mayor) { create_race_for(office_in(port_merritt, "Mayor")) }
  let!(:ward_council) { create_race_for(office_in(ward_4, "City Council")) }
  let!(:governor) { create_race_for(office_in(state, "Governor")) }

  it "invites a visitor who is not signed in to sign in, and still shows the races" do
    get municipality_path(city)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Port Merritt", "Sign in to build a mountain", "On the ballot here", "Mayor", "City Council")
    expect(response.body).to include("Also on every ballot here", "1 state race")
  end

  it "sends a resident to their own ballot" do
    sign_in voter

    get municipality_path(city)

    expect(response.body).to include("Open my ballot", "Build your mountain", "See them on my ballot")
    expect(response.body).not_to include("Pretend vote here")
  end

  it "offers a visitor from elsewhere a pretend vote" do
    sign_in create(:voter, first_name: "Omar", last_name: "Haddad")

    get municipality_path(city)

    expect(response.body).to include("Pretend vote here", "Make a mock election here", new_mock_election_path(jurisdiction_id: port_merritt.id))
  end

  it "shows six races and links to the rest" do
    5.times { |seat| create_race_for(create(:office, position: create(:position, title: "Harbor Commissioner"), jurisdiction: port_merritt, seat_code: "SEAT_#{seat + 1}")) }

    get municipality_path(city)

    expect(response.body.scan('class="place-race"').size).to eq(6)
    expect(response.body).to include("See all 7 races", "Harbor Commissioner", "5 seats")
  end

  it "suggests a mock election when nothing is open here" do
    [ mayor, ward_council ].each { it.update!(status: "completed") }
    sign_in create(:voter)

    get municipality_path(city)

    expect(response.body).to include("No races are open here right now.", "Make a mock election here")
  end

  it "can be bookmarked, and shows up under Saved" do
    sign_in voter

    post engagements_path, params: { engageable_type: "Municipality", engageable_id: city.id, kind: "bookmark" }
    get engagements_path

    expect(voter.engagements.bookmark.sole.engageable).to eq(city)
    expect(response.body).to include("Port Merritt")
  end

  it "leaves out a county that is only the city itself" do
    county = create(:county, name: "Virginia Beach city")
    independent = create(:municipality, :with_jurisdiction, name: "Virginia Beach", county: county, state: county.state)

    get municipality_path(independent)

    expect(response.body).not_to include("Virginia Beach city")
  end
end

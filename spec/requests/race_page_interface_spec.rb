require "rails_helper"

# Each example records what one visitor sees on a race page. The snapshots in
# spec/snapshots/race_page/ are the reviewed record of each permutation;
# `bin/insta review` shows what changed.
RSpec.describe "Race page", type: :request do
  let(:state) { create(:state, name: "Illinois", country: create(:country, name: "United States")) }
  let(:springfield) { create(:municipality, :with_jurisdiction, name: "Springfield", state: state) }
  let(:office) { create(:office, position: create(:position, title: "Mayor"), jurisdiction: springfield.jurisdiction) }

  around { |example| travel_to(Time.zone.local(2026, 10, 20, 12)) { example.run } }

  def race_with_candidates(election_trait = :active, **election_attributes)
    create_race_for(office, election_trait, year: create(:year, year: 2026), **election_attributes).tap do |race|
      [ [ "Alice", "Johnson", "Democratic Party" ], [ "Bob", "Smith", "Independent" ] ].each do |first, last, party|
        create(:candidacy, :active, race: race, party_label: party, citizen: create(:citizen, first_name: first, middle_name: nil, last_name: last))
      end
    end
  end

  def outline(race)
    get race_path(race)
    expect(response).to have_http_status(:ok)
    response.body
  end

  it "invites a signed-out visitor to sign in before rating" do
    expect(outline(race_with_candidates)).to match_snapshot(serializer: :interface)
  end

  it "offers a signed-in voter the mountain for the race" do
    race = race_with_candidates
    sign_in create(:voter, first_name: "Rosa", last_name: "Delgado")
    expect(outline(race)).to match_snapshot(serializer: :interface)
  end

  it "shows an administrator the race's management tools" do
    race = race_with_candidates
    sign_in create(:admin_voter)
    expect(outline(race)).to match_snapshot(serializer: :interface)
  end

  it "marks a mock election and offers an administrator its simulation" do
    race = race_with_candidates(:active, is_mock: true)
    sign_in create(:admin_voter)
    expect(outline(race)).to match_snapshot(serializer: :interface)
  end
end

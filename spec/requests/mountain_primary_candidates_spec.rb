require 'rails_helper'

# A general's off-ballot candidacies for primary candidates stay off a voter's mountain, and out of
# their approvals, until the voter includes them for that race.
RSpec.describe "Primary candidates on the mountain", type: :request do
  let!(:race) { create(:race, :active) }
  let!(:voter) { create(:voter) }
  let(:nominee) { create(:citizen, first_name: "Marisol", last_name: "Okafor") }
  let(:eliminated) { create(:citizen, first_name: "Dwayne", last_name: "Pritchett") }
  let!(:on_ballot) { create(:candidacy, race: race, citizen: nominee, status: "active") }
  let!(:from_primary) do
    create(:candidacy, race: race, citizen: eliminated, status: "active", participation: "off_ballot", primary_candidacy: create(:candidacy, citizen: eliminated))
  end

  before { sign_in voter }

  it "leaves primary candidates off by default and offers to include them" do
    get mountain_path(race, voter_id: voter.id)

    expect(response.body).to include("Okafor")
    expect(response.body).not_to include("ratings[#{from_primary.id}]")
    expect(response.body).to include("1 candidate ran in this office&#39;s primaries but is not on the general ballot.")
    expect(response.body).to include("Include primary candidates")
  end

  it "includes them for this race only once the voter turns them on, and removes them again" do
    other_race = create(:race, :active)

    patch primary_candidates_mountain_path(race), params: { voter_id: voter.id, included: "1" }

    expect(response).to redirect_to(mountain_path(race, voter_id: voter.id))
    expect(voter.includes_primary_candidates?(race)).to be(true)
    expect(voter.includes_primary_candidates?(other_race)).to be(false)
    get mountain_path(race, voter_id: voter.id)
    expect(response.body).to include("ratings[#{from_primary.id}]", "Remove primary candidates")

    patch primary_candidates_mountain_path(race), params: { voter_id: voter.id, included: "0" }

    expect(voter.reload.includes_primary_candidates?(race)).to be(false)
    expect(VoterRacePreference.find_by!(voter: voter, race: race).include_primary_candidates).to be(false)
  end

  it "counts a voter's approval of a primary candidate only while they include them" do
    VoterRacePreference.create!(voter: voter, race: race, include_primary_candidates: true)
    VoterRaceBaseline.create!(voter: voter, race: race, baseline: 250)
    Rating.create!(voter: voter, candidacy: from_primary, rating: 400)
    Rating.create!(voter: voter, candidacy: on_ballot, rating: 300)

    expect(race.aggregate_votes.values_at(on_ballot, from_primary)).to eq([ 1, 1 ])

    voter.include_primary_candidates!(race, false)

    expect(race.aggregate_votes.values_at(on_ballot, from_primary)).to eq([ 1, 0 ])
  end

  it "refuses a rating for a primary candidate the voter has not included" do
    patch mountain_path(race), params: { voter_id: voter.id, ratings: { from_primary.id => "400" } }

    expect(Rating.where(candidacy: from_primary)).to be_empty
  end
end

require "rails_helper"

# Anyone can make a mock election for a class or a test: invented candidates in a real place. Its offices
# stay inactive and its citizens are marked fictional, and removing it removes them too.
RSpec.describe MockElection do
  let(:teacher) { create(:voter, first_name: "Imani", last_name: "Brooks") }
  let(:city) { create(:jurisdiction, jurisdictionable: create(:municipality, name: "Port Merritt")) }
  let(:attributes) do
    {
      name: "School board, classroom edition", description: "Made by a civic educator for one class",
      election_date: Date.new(2026, 11, 17), jurisdiction_id: city.id, creator: teacher,
      races: [ { "title" => "School Board", "candidates" => [ "Avery Lin", "Jordan Okafor-Reyes", "" ] } ]
    }
  end

  it "makes a mock election with inactive offices and fictional candidates" do
    election = described_class.new(**attributes).save!

    expect(election).to have_attributes(is_mock: true, mode: "mock", status: "upcoming", creator: teacher)
    expect(election.year.year).to eq(2026)
    race = election.races.sole
    expect(race.office).to have_attributes(is_active: false, jurisdiction: city)
    expect(race.candidates.map(&:full_name)).to contain_exactly("Avery Lin", "Jordan Okafor-Reyes")
    expect(race.candidates).to all(be_fictional)
    expect(Election.created_by(teacher)).to eq([ election ])
  end

  it "needs a race with a title and at least two candidates" do
    mock = described_class.new(**attributes, races: [ { title: "School Board", candidates: [ "Avery Lin" ] } ])

    expect(mock).not_to be_valid
    expect(mock.errors[:races]).to include("each need a title and at least two candidates")
  end

  it "removes the election with the offices and citizens invented for it" do
    election = described_class.new(**attributes).save!
    real_citizen = create(:citizen, first_name: "Dana", last_name: "Okafor")

    expect { election.destroy_mock! }.to change(Election, :count).by(-1)
      .and change(Office, :count).by(-1)
      .and change(Citizen.fictional, :count).by(-2)
    expect(real_citizen.reload).to be_persisted
  end
end

# A historical race replays a finished election with approval voting, holding back the certified result
# until the voter has saved their own mountain.
RSpec.describe OfficialResult do
  let(:race) { create(:race, :historical, status: "completed", decided_by: "plurality") }
  let(:winner) { create(:candidacy, race: race) }
  let(:voter) { create(:voter) }

  it "reveals the certified result only after the voter saves a mountain" do
    described_class.create!(race: race, candidacy: winner, votes: 18_204, vote_share: 41.3, winner: true)

    expect(race.official_results_revealed_to?(voter)).to be(false)
    Mountain.new(voter: voter, race: race).publish!(ratings: { winner.id => 300 }, baseline: 200)

    expect(race.official_results_revealed_to?(voter)).to be(true)
    expect(race.official_results.winners.sole.candidacy).to eq(winner)
    expect(race.mode_for(voter)).to eq("historical")
  end

  it "only records candidacies that ran in the race" do
    result = described_class.new(race: race, candidacy: create(:candidacy), votes: 10)

    expect(result).not_to be_valid
    expect(result.errors[:candidacy]).to include("must have run in this race")
  end
end

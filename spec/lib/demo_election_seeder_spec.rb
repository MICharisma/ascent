require "rails_helper"
require Rails.root.join("db", "seeds", "demo_election_seeder")

# Demo data fills a real election with invented, clearly marked activity, the same every time, and
# clears without touching anything else.
RSpec.describe DemoElectionSeeder do
  let(:county) { create(:jurisdiction, :county) }
  let(:election) { create(:election, jurisdiction: county, status: "upcoming") }
  let!(:races) do
    5.times.map do |n|
      create(:race, election: election, office: create(:office, jurisdiction: county, seat_code: "TOWN_#{n}")).tap do |race|
        create_list(:candidacy, 3, race: race)
      end
    end
  end
  let!(:real_voter) { create(:voter, email: "real.citizen@example.com") }

  it "builds resident and visitor mountains, leaving the last race with a small sample" do
    summary = described_class.new(election).seed!

    expect(summary).to include(voters: 41, races_with_mountains: 5)
    expect(RaceResults.new(races.last).mountain_count).to eq(DemoElectionSeeder::SHORT_RACE_MOUNTAINS)
    expect(VoterRaceBaseline.where(race: races.first).group(:counted_as).count.keys).to contain_exactly("resident", "visitor")
    expect(Organization.where("name LIKE ?", "%(demo)")).to exist
  end

  it "gives the demo resident saved races, a draft and a followed election" do
    seeder = described_class.new(election)
    seeder.seed!
    resident = Voter.find_by!(email: seeder.demo_resident_email)

    expect(resident.mountain_progress(election.races).values.tally).to eq("saved" => 3, "started" => 1)
    expect(resident.engagements.follow.sole.engageable).to eq(election)
  end

  it "makes the same data every time, and clears only its own" do
    first = described_class.new(election).seed!
    second = described_class.new(election).seed!

    expect(second).to eq(first)

    described_class.new(election).clear!

    expect(Voter.where("email LIKE ?", "%@#{DemoElectionSeeder::DOMAIN}")).to be_empty
    expect(Organization.where("name LIKE ?", "%(demo)")).to be_empty
    expect(real_voter.reload).to be_persisted
  end
end

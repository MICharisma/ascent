require "rails_helper"

RSpec.describe "Mountain scenario factories", type: :model do
  {
    mountain_scenario: [ 8, 4 ],
    crowded_primary_mountain: [ 12, 7 ],
    knife_edge_mountain: [ 8, 4 ],
    enthusiastic_mountain: [ 8, 6 ],
    selective_mountain: [ 8, 2 ],
    polarized_mountain: [ 8, 4 ]
  }.each do |factory, (candidate_count, approval_count)|
    it "creates a saved Mountain for #{factory}" do
      scenario = create(factory)
      race = scenario.fetch(:race)
      voter = scenario.fetch(:voter)
      mountain = Mountain.new(race: race, voter: voter)

      expect(race).to be_mock
      expect(race.status).to eq("active")
      expect(race.candidacies.count).to eq(candidate_count)
      expect(mountain.rated_count).to eq(candidate_count)
      expect(mountain.progress).to eq("saved")
      expect(mountain.baseline).to eq(scenario.fetch(:baseline).baseline)
      expect(mountain.approved_candidacies.count).to eq(approval_count)
    end
  end
end

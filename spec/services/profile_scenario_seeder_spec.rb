require "rails_helper"
require Rails.root.join("db/seeds/profile_scenario_seeder")

RSpec.describe ProfileScenarioSeeder do
  before { create(:state, :with_jurisdiction, name: "New York") }

  it "builds repeatable fictional profiles with shared approaches and different positions" do
    result = described_class.new.seed!
    election = Election.find(result[:election_id])

    expect(election).to be_is_mock
    expect(election.candidates.size).to eq(3)
    expect(election.candidates).to all(be_fictional)
    expect(Stance.where(candidacy: election.candidacies).count).to eq(18)
    expect(Stance.where(candidacy: election.candidacies).group(:approach_id).count.values).to eq([ 3 ] * 6)
    housing = election.candidacies.map { it.stances.joins(:approach).find_by!(approaches: { title: "Build more homes near transit" }).explanation }
    expect(housing.uniq.size).to eq(3)
    expect(election.candidates.find_by!(first_name: "Marisol").images.sole.url).to end_with("marisol-vega.png")
    expect(election.candidates.find_by!(first_name: "Marisol").images.sole.file).to be_attached

    expect { described_class.new.seed! }.not_to change { [ Election.count, Citizen.count, Candidacy.count, Stance.count, Communication.count, Channel.count,
      Image.count, ImagePlacement.count, ActiveStorage::Blob.count, ActiveStorage::Attachment.count ] }
  end
end

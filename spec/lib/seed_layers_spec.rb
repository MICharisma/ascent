require "rails_helper"
require Rails.root.join("db", "seeds", "seed_layers")

RSpec.describe SeedLayers do
  describe "db:seed" do
    it "leaves reference data untouched when automatic seeding is disabled" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SKIP_SEEDS").and_return("1")
      expect(described_class).not_to receive(:seed_reference!)

      load Rails.root.join("db", "seeds.rb")
    end

    it "keeps the normal reference seed entrypoint enabled by default" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SKIP_SEEDS").and_return(nil)
      expect(described_class).to receive(:seed_reference!)

      load Rails.root.join("db", "seeds.rb")
    end
  end

  describe ".seed_reference!" do
    before do
      described_class.send(:load_seeders!)
    end

    it "loads only the factual reference seeders" do
      expect(CountrySeeder).to receive(:seed).with(SeedDataPaths.file("countries.yml"))
      expect(StateSeeder).to receive(:seed).with([
        SeedDataPaths.file("us_states.yml"),
        SeedDataPaths.file("canadian_provinces.yml")
      ])
      expect(MunicipalitySeeder).to receive(:seed)
      expect(YearSeeder).to receive(:seed)
      expect(GubernatorialRaceSeeder).to receive(:seed)
      expect(SeedManifests).to receive(:seed)
      expect(VoterSeeder).not_to receive(:seed)
      expect(ElectionSeeder).not_to receive(:seed)

      upcoming = create(:race, status: "upcoming")
      completed = create(:race, status: "completed")
      cancelled = create(:race, status: "cancelled")
      seeded_race = nil
      allow(GubernatorialRaceSeeder).to receive(:seed) do
        seeded_race = create(:race, status: "upcoming")
      end

      described_class.seed_reference!

      expect(upcoming.reload.status).to eq("active")
      expect(seeded_race.reload.status).to eq("active")
      expect(completed.reload.status).to eq("completed")
      expect(cancelled.reload.status).to eq("cancelled")
    end
  end

  describe ".seed_simulated!" do
    before do
      described_class.send(:load_seeders!)
      allow(described_class).to receive(:seed_reference!)
    end

    it "adds the simulated experience after the reference layer" do
      SeedLayers::SIMULATED_SEEDER_FILES.each do |filename|
        constant_name = filename.delete_suffix("_seeder").camelize.concat("Seeder")
        expect(constant_name.constantize).to receive(:seed)
      end

      described_class.seed_simulated!

      expect(described_class).to have_received(:seed_reference!)
    end
  end
end

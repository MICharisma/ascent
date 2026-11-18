require "rails_helper"

RSpec.describe "Minimum contributor seed examples" do
  let(:root) { Rails.root.join("db/seeds/ascent_seed_data/examples") }
  let(:models) { [ Country, State, District, Position, Office, Election, Race, Citizen, Candidacy, Channel, Jurisdiction, EntityCode ] }

  %w[yml json].each do |format|
    it "imports the #{format} election graph with only its documented Year prerequisite" do
      expect(models.map(&:count)).to all(eq(0))
      year = Year.create!(year: 2026, is_even_year: true, is_presidential_year: false)
      importer = Seeds::LibraryImporter.new
      importer.call([ root.join("minimum_election.#{format}").to_s ])

      expect(importer.report[:created].size).to eq(10)
      expect(importer.report[:conflicts]).to be_empty
      candidacy = Candidacy.sole
      expect(candidacy.citizen.full_name).to eq("Marisol Vega")
      expect(candidacy.race.election.year).to eq(year)
      expect(candidacy.race.election).to be_is_mock
      expect(candidacy.office.branch).to eq("legislative")
      district = District.sole
      state = State.sole
      expect(district.jurisdiction.parent).to eq(state.jurisdiction)
      expect(state.jurisdiction.parent).to eq(Country.sole.jurisdiction)
      expect(candidacy.office.jurisdiction).to eq(district.jurisdiction)
      expect(candidacy.election.jurisdiction).to eq(state.jurisdiction)
      expect(Channel.sole).to have_attributes(owner: candidacy.citizen, platform: "website", official: true)

      counts = -> { models.map(&:count) }
      expect { importer.call([ root.join("minimum_election.yml").to_s, root.join("minimum_election.json").to_s ]) }.not_to change(&counts)
      expect(importer.report[:conflicts]).to be_empty

      importer.call([ root.join("government_branches.#{format}").to_s ])
      expect(Position.count).to eq(3)
      expect(importer.report[:created].size).to eq(2)
      expect(importer.report[:conflicts]).to be_empty
    end

    it "imports all three government branches from #{format} without any prerequisite" do
      expect(models.map(&:count)).to all(eq(0))
      importer = Seeds::LibraryImporter.new
      importer.call([ root.join("government_branches.#{format}").to_s ])

      expect(Position.order(:branch).pluck(:title, :branch)).to eq([
        [ "State Representative", "legislative" ], [ "Governor", "executive" ], [ "State Judge", "judicial" ]
      ])
      expect(importer.report[:created].size).to eq(3)
      expect(importer.report[:conflicts]).to be_empty
      expect { importer.call([ root.join("government_branches.yml").to_s, root.join("government_branches.json").to_s ]) }.not_to change(Position, :count)
    end
  end

  it "reports a missing Year instead of silently creating one or leaving a partial graph" do
    expect(Year.count).to eq(0)
    counts = -> { models.map(&:count) }
    expect do
      expect { Seeds::LibraryImporter.new.call([ root.join("minimum_election.yml").to_s ]) }
        .to raise_error(Seeds::LibraryImporter::Error, /missing Year 2026/)
    end.not_to change(&counts)
  end

  it "imports after the documented foundation-year setup" do
    require Rails.root.join("db/seeds/data_paths")
    require Rails.root.join("db/seeds/year_seeder")
    expect { YearSeeder.seed }.to output(/Seeded \d+ years/).to_stdout
    expect(Year.find_by!(year: 2026)).to have_attributes(is_even_year: true, is_presidential_year: false)

    importer = Seeds::LibraryImporter.new
    importer.call([ root.join("minimum_election.yml").to_s ])
    expect(importer.report[:created].size).to eq(10)
    expect(importer.report[:conflicts]).to be_empty
  end
end

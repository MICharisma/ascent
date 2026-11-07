require "rails_helper"
require Rails.root.join("db", "seeds", "data_paths")

RSpec.describe Seeds::BallotRows do
  let(:paths) { described_class.paths(SeedDataPaths.primary_root) }

  it "reads every 2026 state ballot file with the required columns" do
    expect(paths.map { |path| path.split("/races/2026/").last.split("/").first }.uniq)
      .to contain_exactly("connecticut", "florida", "massachusetts", "new_york", "virginia")

    rows = paths.flat_map { |path| described_class.rows_from(path) }

    expect(rows.size).to eq(7719)
    expect(rows).to all(include(*described_class::REQUIRED_KEYS))
    expect(rows.map { |row| row.fetch("state") }.uniq).to contain_exactly("CT", "FL", "MA", "NY", "VA")
    expect(rows.map { |row| row.fetch("election_date") }.uniq).to eq([ "2026-11-03" ])
  end

  it "maps every federal and state office title to a shared position" do
    titles = paths.reject { |path| path.include?("/local/") }
                  .flat_map { |path| described_class.rows_from(path) }
                  .map { |row| row.fetch("office") }.uniq

    expect(titles - described_class::STATE_LEVEL_OFFICES.keys).to be_empty
  end

  describe ".name_parts" do
    {
      "Christopher J. Gallant" => { first_name: "Christopher", middle_name: "J.", last_name: "Gallant" },
      "Angelo J. Puppolo, Jr." => { first_name: "Angelo", middle_name: "J.", last_name: "Puppolo, Jr." },
      "Henry White Jr." => { first_name: "Henry", middle_name: nil, last_name: "White Jr." },
      "Charles E. \"Chuck\" Tiernan, III" => { first_name: "Charles", middle_name: "E. \"Chuck\"", last_name: "Tiernan, III" },
      "Healey" => { first_name: nil, middle_name: nil, last_name: "Healey" }
    }.each do |printed_name, parts|
      it "splits #{printed_name.inspect} so the full name reads as printed" do
        expect(described_class.name_parts(printed_name)).to eq(parts)
        expect(Citizen.new(parts).full_name).to eq(printed_name)
      end
    end
  end

  it "names counties and capitalized places consistently" do
    expect(%w[Erie ACCOMACK\ COUNTY Kings\ (NYC)].map { |name| described_class.county_name(name) })
      .to eq([ "Erie County", "Accomack County", "Kings County" ])
    expect(described_class.title_case("TOWN OF CICERO")).to eq("Town of Cicero")
  end
end

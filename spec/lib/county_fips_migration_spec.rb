require "rails_helper"
require Rails.root.join("db/migrate/20261028200000_rename_county_code_to_fips")

RSpec.describe RenameCountyCodeToFips do
  it "preserves leading zeros and fills missing FIPS from existing county Census IDs" do
    country = create(:country, code: "US")
    state = create(:state, country: country)
    county = create(:county, :with_jurisdiction, state: state, fips: "01001")
    missing = create(:county, :with_jurisdiction, state: state)
    missing.jurisdiction.update!(census_class: "G4020", census_geoid: "01003")
    migration = described_class.new

    migration.down
    expect(County.connection.select_value("SELECT code FROM counties WHERE id = #{County.connection.quote(county.id)}")).to eq("01001")
    migration.up
    County.reset_column_information
    expect(county.reload.fips).to eq("01001")
    expect(missing.reload.fips).to eq("01003")
  ensure
    County.reset_column_information
  end
end

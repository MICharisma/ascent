require "rails_helper"
require Rails.root.join("db/migrate/20261110173000_convert_stored_person_types")
require Rails.root.join("db/migrate/20261110173100_reissue_citizen_codes")

RSpec.describe "Citizen compatibility migrations" do
  def issued(code)
    EntityCode.find_by!(namespace: "MIC", catalog: "ASC", code: code)
  end

  def legacy_citizen
    create(:citizen, entity_code: "PERSON-LEGACY").tap do |citizen|
      EntityCode.create!(namespace: "MIC", catalog: "ASC", code: citizen.entity_code,
        canonical_code: citizen.entity_code, record: citizen)
    end
  end

  it "converts legacy channel and code references without changing their owners" do
    citizen = legacy_citizen
    channel = create(:channel, owner: citizen)
    organization = create(:organization)
    other = create(:channel, owner: organization)
    code = issued(citizen.entity_code)
    code.update_column(:record_type, "Person")
    channel.update_column(:owner_type, "Person")

    migration = ConvertStoredPersonTypes.new
    migration.up

    expect(code.reload.record).to eq(citizen)
    expect(channel.reload.owner).to eq(citizen)
    expect(other.reload.owner).to eq(organization)

    migration.down
    expect(code.reload.record_type).to eq("Person")
    expect(channel.reload.owner_type).to eq("Person")
    expect(other.reload.owner_type).to eq("Organization")
  end

  it "issues Citizen codes once and keeps Person codes as resolvable aliases" do
    citizen = legacy_citizen
    original = issued(citizen.entity_code)
    migration = ReissueCitizenCodes.new

    migration.up
    migration.up

    expect(citizen.reload.entity_code).to eq("CITIZEN-LEGACY")
    expect(original.reload).to be_alias
    expect(original.record).to eq(citizen)
    expect(issued("CITIZEN-LEGACY").record).to eq(citizen)
    expect(EntityCode.where(record: citizen).count).to eq(2)
  end

  it "refuses to take a code that belongs to another record" do
    legacy = legacy_citizen
    holder = create(:citizen, entity_code: "CITIZEN-LEGACY")
    EntityCode.create!(namespace: "MIC", catalog: "ASC", code: holder.entity_code,
      canonical_code: holder.entity_code, record: holder)

    expect { ReissueCitizenCodes.new.up }.to raise_error(/would claim 1 existing codes/)
    expect(legacy.reload.entity_code).to eq("PERSON-LEGACY")
    expect(issued("CITIZEN-LEGACY").record).to eq(holder)
  end

  it "reverses converted preferences while retaining published Citizen aliases" do
    legacy = legacy_citizen
    current = create(:citizen, entity_code: "CITIZEN-CURRENT")
    migration = ReissueCitizenCodes.new
    migration.up
    migration.down

    expect(legacy.reload.entity_code).to eq("PERSON-LEGACY")
    expect(issued("CITIZEN-LEGACY")).to be_alias
    expect(issued("CITIZEN-LEGACY").record).to eq(legacy)
    expect(current.reload.entity_code).to eq("CITIZEN-CURRENT")
  end
end

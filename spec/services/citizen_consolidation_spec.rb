require "rails_helper"

RSpec.describe CitizenConsolidation do
  let(:entity_id) { SecureRandom.uuid }
  let(:code) { "MIC-RZZ-VEGA" }
  let!(:survivor) { create(:citizen, first_name: "Marisol", middle_name: nil, last_name: "Vega", entity_code: code, username: "vega_ms_2a", username_status: "provisional", email: nil, bio: nil, birth_date: nil) }
  let!(:duplicate) { create(:citizen, first_name: "Marisol", middle_name: nil, last_name: "Vega", entity_code: "CITIZEN-VEGA_MS_3B", username: "vega_ms_3b", username_status: "provisional", email: nil, bio: nil, birth_date: nil) }

  before do
    RizzSync.create!(citizen: survivor, state: "synced", rizz_entity_id: entity_id, rizz_code: code)
    RizzSync.create!(citizen: duplicate, state: "merge_needed", rizz_entity_id: entity_id, rizz_code: code)
    EntityCode.create!(namespace: "MIC", catalog: "ASC", code: "CITIZEN-VEGA_MS_2A", canonical_code: code, record: survivor)
    EntityCode.create!(namespace: "MIC", catalog: "ASC", code: duplicate.entity_code, canonical_code: duplicate.entity_code, record: duplicate)
  end

  it "previews identity groups and same-race entries without changing them" do
    race = create(:race)
    first = create(:candidacy, citizen: survivor, race: race)
    second = create(:candidacy, citizen: duplicate, race: race)
    expect { @plan = described_class.preview }.not_to change(CitizenMerge, :count)
    expect(@plan.fetch("groups").first).to include("survivor_id" => survivor.id, "duplicate_ids" => [ duplicate.id ], "same_race_candidacies" => [ [ first.id, second.id ] ])
    expect(second.reload.citizen_id).to eq(duplicate.id)
  end

  it "moves candidacies and personal links while preserving their attached records and old codes" do
    candidacy = create(:candidacy, citizen: duplicate)
    rating = create(:rating, candidacy: candidacy)
    voter = create(:voter)
    engagement = Engagement.create!(voter: voter, engageable: duplicate, kind: "follow")
    channel = Channel.create!(owner: duplicate, platform: "website", handle: "marisolvega.example", url: "https://marisolvega.example")
    image = Image.create!(url: "https://marisolvega.example/portrait.jpg")
    placement = ImagePlacement.create!(subject: duplicate, image: image, position: 0)
    endorsement = Endorsement.create!(endorser: duplicate, candidacy: candidacy, kind: "public")
    plan = described_class.preview

    expect { described_class.apply(plan, performed_by: "maintainer") }.to change(Citizen, :count).by(-1)
    expect(candidacy.reload.citizen_id).to eq(survivor.id)
    expect(rating.reload.candidacy_id).to eq(candidacy.id)
    expect([ engagement.reload.engageable, channel.reload.owner, placement.reload.subject, endorsement.reload.endorser ]).to all(eq(survivor))
    binding = EntityCode.find_by!(code: "CITIZEN-VEGA_MS_3B")
    expect(binding.resolved_record).to eq(survivor)
    expect(binding.canonical_code).to eq(code)
    merge = CitizenMerge.find_by!(old_citizen_id: duplicate.id)
    expect(merge.snapshot.fetch("citizens").map { it.fetch("id") }).to contain_exactly(survivor.id, duplicate.id)
    expect(described_class.apply(plan, performed_by: "maintainer").first.fetch("status")).to eq("already_applied")
    expect(described_class.preview.fetch("groups")).to be_empty
  end

  it "retains distinct candidacy IDs even when they share a race" do
    race = create(:race)
    first = create(:candidacy, citizen: survivor, race: race)
    second = create(:candidacy, citizen: duplicate, race: race)
    described_class.apply(described_class.preview, performed_by: "maintainer")
    expect(Candidacy.where(citizen: survivor, race: race).pluck(:id)).to contain_exactly(first.id, second.id)
  end

  it "rejects stale previews without moving any records" do
    plan = described_class.preview
    duplicate.update!(first_name: "Maria")
    expect { described_class.apply(plan, performed_by: "maintainer") }.to raise_error(described_class::Conflict, /changed since preview/)
    expect(Citizen.exists?(duplicate.id)).to be(true)
    expect(CitizenMerge.count).to eq(0)
  end

  it "refuses profile conflicts and mismatched Rizz codes" do
    survivor.update!(birth_date: "1980-05-10")
    duplicate.update!(birth_date: "1981-05-10")
    expect { described_class.preview }.to raise_error(described_class::Conflict, /profile fields/)
    duplicate.update!(birth_date: nil)
    duplicate.rizz_sync.update!(rizz_code: "MIC-RZZ-SOMEONEELSE")
    expect { described_class.preview }.to raise_error(described_class::Conflict, /code differs/)
  end

  it "deduplicates identical engagements with the originals retained in the audit" do
    voter = create(:voter)
    Engagement.create!(voter: voter, engageable: survivor, kind: "follow")
    old = Engagement.create!(voter: voter, engageable: duplicate, kind: "follow")
    described_class.apply(described_class.preview, performed_by: "maintainer")
    expect(Engagement.where(voter: voter, engageable: survivor, kind: "follow").count).to eq(1)
    expect(CitizenMerge.last.snapshot.fetch("engagements").map { it.fetch("id") }).to include(old.id)
  end

  it "replays consolidated seed aliases without recreating a Citizen or reporting profile conflicts" do
    described_class.apply(described_class.preview, performed_by: "maintainer")
    path = Rails.root.join("tmp/consolidated_citizens_spec.yml")
    path.write({ "format" => "micharisma-seeds/v1", "namespace" => "MIC", "catalog" => "ASC", "records" => [
      { "type" => "Citizen", "code" => "CITIZEN-VEGA_MS_2A", "aliases" => [ "CITIZEN-VEGA_MS_3B" ],
        "attributes" => { "username" => "vega_ms_2a", "username_status" => "provisional", "first_name" => "Marisol", "last_name" => "Vega" } }
    ] }.to_yaml)
    report = nil
    expect { report = Seeds::LibraryImporter.new.call([ path.to_s ]) }.not_to change(Citizen, :count)
    expect(report[:conflicts]).to be_empty
    expect(EntityCode.find_by!(code: "CITIZEN-VEGA_MS_3B").resolved_record).to eq(survivor)
  ensure
    path&.delete if path&.exist?
  end
end

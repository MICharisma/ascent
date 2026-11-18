require 'rails_helper'

RSpec.describe Citizen, type: :model do
  it "reloads Citizen links across every supported polymorphic relationship" do
    citizen = create(:citizen, entity_code: "CITIZEN-VEGA_MS_2A")
    channel = create(:channel, owner: citizen)
    endorsement = create(:endorsement, endorser: citizen)
    engagement = create(:engagement, engageable: citizen)
    placement = create(:image_placement, subject: citizen)
    binding = EntityCode.create!(namespace: "MIC", catalog: "ASC", code: citizen.entity_code,
      canonical_code: citizen.entity_code, record: citizen)

    expect([ channel.reload.owner, endorsement.reload.endorser, engagement.reload.engageable,
      placement.reload.subject, binding.reload.record ]).to all(eq(citizen))
    expect([ channel.owner_type, endorsement.endorser_type, engagement.engageable_type,
      placement.subject_type, binding.record_type ]).to all(eq("Citizen"))
    expect(placement.image.citizens).to include(citizen)
  end

  it "hides a citizen only from the voter who hid that profile" do
    citizen = create(:citizen)
    engagement = create(:engagement, engageable: citizen, kind: :hide)

    expect(Citizen.visible_to(engagement.voter)).not_to include(citizen)
    expect(Citizen.visible_to(create(:voter))).to include(citizen)
    expect(Citizen.visible_to(nil)).to include(citizen)
  end

  describe "usernames" do
    it "accepts a provisional generated username" do
      expect(build(:citizen, username: "kuhn_dawn_ny_ad_7", username_status: "provisional")).to be_valid
    end

    it "requires a status once a username is issued" do
      citizen = build(:citizen, username: "kuhn_dawn_ny_ad_7", username_status: nil)

      expect(citizen).not_to be_valid
      expect(citizen.errors[:username_status]).to be_present
    end

    it "keeps usernames unique and limited to code-safe characters" do
      create(:citizen, username: "kuhn_dawn_ny_ad_7", username_status: "provisional")

      expect(build(:citizen, username: "kuhn_dawn_ny_ad_7", username_status: "provisional")).not_to be_valid
      expect(build(:citizen, username: "dawn.kuhn", username_status: "verified")).not_to be_valid
    end

    it "allows citizens without a username" do
      expect(build(:citizen, username: nil, username_status: nil)).to be_valid
    end
  end
end

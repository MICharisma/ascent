require "rails_helper"

RSpec.describe CandidacyConsolidation do
  let(:citizen) { create(:citizen) }
  let(:race) { create(:race) }
  let!(:survivor) { create(:candidacy, citizen: citizen, race: race, announcement_date: nil, platform_summary: nil, party_label: nil, entity_code: "CANDIDACY-MARISOL-COUNCIL-A") }
  let!(:duplicate) { create(:candidacy, citizen: citizen, race: race, announcement_date: nil, platform_summary: nil, party_label: nil, entity_code: "CANDIDACY-MARISOL-COUNCIL-B") }

  before do
    CitizenMerge.create!(old_citizen_id: 987654321, citizen: citizen, rizz_entity_id: SecureRandom.uuid, performed_by: "maintainer", snapshot: {})
    [ survivor, duplicate ].each do |row|
      EntityCode.create!(namespace: "MIC", catalog: "ASC", code: row.entity_code, canonical_code: row.entity_code, record: row)
    end
  end

  it "previews only same-race entries for consolidated Citizens" do
    other = create(:candidacy, citizen: citizen)
    plan = described_class.preview
    expect(plan.fetch("groups").one?).to be(true)
    expect(plan.fetch("groups").first).to include("survivor_id" => survivor.id, "duplicate_ids" => [ duplicate.id ])
    expect(Candidacy.exists?(other.id)).to be(true)
    expect(CandidacyMerge.count).to eq(0)
  end

  it "moves ratings, history, stances, evidence, results and personal links without changing their identities" do
    voter = create(:voter)
    rating = create(:rating, candidacy: duplicate, voter: voter, rating: 375)
    archive = RatingArchive.create!(voter: voter, candidacy: duplicate, rating: 250, archived_at: 1.day.ago, reason: "Earlier assessment")
    stance = create(:stance, candidacy: duplicate)
    communication = create(:communication)
    evidence = StanceEvidence.create!(stance: stance, communication: communication, relation: "states", quote: "Support local schools")
    feature = CommunicationFeature.create!(communication: communication, candidacy: duplicate)
    result = OfficialResult.create!(race: race, candidacy: duplicate, votes: 1200)
    channel = Channel.create!(owner: duplicate, platform: "website", handle: "marisolvega.example", url: "https://marisolvega.example")
    engagement = Engagement.create!(voter: voter, engageable: duplicate, kind: "follow")
    image = Image.create!(url: "https://marisolvega.example/profile.jpg")
    placement = ImagePlacement.create!(subject: duplicate, image: image, position: 1)
    draft = MountainDraft.create!(voter: voter, race: race, ratings: { duplicate.id.to_s => nil })
    plan = described_class.preview

    described_class.apply(plan, performed_by: "maintainer")

    expect([ rating.reload.candidacy, archive.reload.candidacy, stance.reload.candidacy, feature.reload.candidacy, result.reload.candidacy ]).to all(eq(survivor))
    expect(rating.rating).to eq(375)
    expect(evidence.reload.stance_id).to eq(stance.id)
    expect([ channel.reload.owner, engagement.reload.engageable, placement.reload.subject ]).to all(eq(survivor))
    expect(draft.reload.ratings).to eq(survivor.id.to_s => nil)
    expect(EntityCode.find_by!(code: duplicate.entity_code).resolved_record).to eq(survivor)
    expect(CandidacyMerge.find_by!(old_candidacy_id: duplicate.id).snapshot.fetch("ratings").first.fetch("id")).to eq(rating.id)
    expect(described_class.apply(plan, performed_by: "maintainer").first.fetch("status")).to eq("already_applied")
    expect(described_class.preview.fetch("groups")).to be_empty
  end

  it "combines identical ballot lines and their party endorsements with originals in the audit" do
    party = Party.create!(name: "Republican", state: create(:state))
    [ survivor, duplicate ].each { BallotLine.create!(candidacy: it, party: party, kind: "party", label: "Republican", position: 1) }
    old_line = duplicate.ballot_lines.first
    old_endorsement = old_line.endorsement
    described_class.apply(described_class.preview, performed_by: "maintainer")
    expect(survivor.ballot_lines.count).to eq(1)
    expect(survivor.endorsements.count).to eq(1)
    audit = CandidacyMerge.last.snapshot
    expect(audit.fetch("ballot_lines").map { it.fetch("id") }).to include(old_line.id)
    expect(audit.fetch("endorsements").map { it.fetch("id") }).to include(old_endorsement.id)
  end

  it "keeps an on-ballot candidacy and remaps general-primary links across the whole batch" do
    general_race = create(:race)
    active = create(:candidacy, citizen: citizen, race: general_race, announcement_date: nil, platform_summary: nil, party_label: nil)
    off_ballot = create(:candidacy, citizen: citizen, race: general_race, primary_candidacy: duplicate, participation: "off_ballot", announcement_date: nil, platform_summary: nil, party_label: nil)
    unrelated_general = create(:candidacy, citizen: citizen, primary_candidacy: duplicate, participation: "off_ballot")
    plan = described_class.preview
    expect(plan.fetch("groups").size).to eq(2)
    described_class.apply(plan, performed_by: "maintainer")
    expect(Candidacy.exists?(off_ballot.id)).to be(false)
    expect(active.reload.primary_candidacy_id).to be_nil
    expect(unrelated_general.reload.primary_candidacy_id).to eq(survivor.id)
    expect(CandidacyMerge.find_by!(old_candidacy_id: off_ballot.id).snapshot.fetch("candidacies").find { it["id"] == off_ballot.id }.fetch("primary_candidacy_id")).to eq(duplicate.id)
  end

  it "rolls back the batch when existing ratings disagree" do
    voter = create(:voter)
    create(:rating, candidacy: survivor, voter: voter, rating: 400)
    create(:rating, candidacy: duplicate, voter: voter, rating: 200)
    expect { described_class.apply(described_class.preview, performed_by: "maintainer") }.to raise_error(described_class::Conflict, /Rating/)
    expect(Candidacy.exists?(duplicate.id)).to be(true)
    expect(CandidacyMerge.count).to eq(0)
    expect(Rating.where(voter: voter).pluck(:rating)).to contain_exactly(400, 200)
  end

  it "rejects conflicting draft values, including a removal versus a rating" do
    voter = create(:voter)
    MountainDraft.create!(voter: voter, race: race, ratings: { survivor.id.to_s => 300, duplicate.id.to_s => nil })
    expect { described_class.apply(described_class.preview, performed_by: "maintainer") }.to raise_error(described_class::Conflict, /draft ratings/)
    expect(Candidacy.exists?(duplicate.id)).to be(true)
    expect(CandidacyMerge.count).to eq(0)
  end

  it "rejects stale previews and different races before moving records" do
    plan = described_class.preview
    duplicate.update!(platform_summary: "More local schools")
    expect { described_class.apply(plan, performed_by: "maintainer") }.to raise_error(described_class::Conflict, /changed since preview/)
    another = create(:candidacy, citizen: citizen)
    expect { described_class.new([ survivor.id, another.id ]).plan }.to raise_error(described_class::Conflict, /Citizen and race/)
  end
end

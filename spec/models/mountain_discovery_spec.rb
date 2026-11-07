require "rails_helper"

RSpec.describe MountainDiscovery do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.local(2026, 10, 31, 12) }
  let(:old_time) { now - 8.days }
  let(:ranked) { described_class.new(Race.active, now: now).races }

  around { |example| travel_to(now) { example.run } }

  def contested_race(**attributes)
    create(:race, :active, **attributes).tap { create_list(:candidacy, 2, race: it) }
  end

  it "requires two contenders still on the ballot, without counting withdrawn or primary-only candidates" do
    eligible = contested_race
    create(:race, :active)
    single = create(:race, :active)
    create(:candidacy, race: single)
    create(:candidacy, race: single, status: "withdrawn")
    create(:candidacy, race: single, status: "disqualified")
    create(:candidacy, race: single, participation: "inactive")
    create(:candidacy, race: single, participation: "off_ballot", primary_candidacy: create(:candidacy))
    duplicate = create(:race, :active)
    citizen = create(:citizen)
    create_list(:candidacy, 2, race: duplicate, citizen: citizen)
    contested_race(status: "completed")

    expect(ranked.pluck(:id)).to eq([ eligible.id ])
    expect(ranked.first.mountain_candidate_count).to eq(2)
  end

  it "counts saved mountains once each, including residents and visitors, rather than counting candidate ratings" do
    fewer = contested_race
    more = contested_race
    voter = create(:voter)
    create(:voter_race_baseline, race: fewer, voter: voter, updated_at: old_time)
    fewer.candidacies.each { create(:rating, candidacy: it, voter: voter, updated_at: old_time) }
    create(:voter_race_baseline, race: more, updated_at: old_time, counted_as: "resident")
    create(:voter_race_baseline, race: more, updated_at: old_time, counted_as: "visitor")

    expect(ranked.map(&:id)).to eq([ more.id, fewer.id ])
    expect(ranked.map(&:saved_mountain_count)).to eq([ 2, 1 ])
  end

  it "lets recent participation lift a race above one with more older votes" do
    older = contested_race
    recent = contested_race
    create_list(:voter_race_baseline, 5, race: older, updated_at: old_time)
    create_list(:voter_race_baseline, 2, race: recent)

    expect(ranked.map(&:id)).to eq([ recent.id, older.id ])
    expect(ranked.map(&:recent_mountain_count)).to eq([ 2, 0 ])
  end

  it "counts a recent saver once despite multiple rating edits and includes the seven-day boundary" do
    race = contested_race
    voter = create(:voter)
    create(:voter_race_baseline, race: race, voter: voter, updated_at: now - 7.days)
    race.candidacies.each { create(:rating, candidacy: it, voter: voter, updated_at: now) }
    create(:voter_race_baseline, race: race, updated_at: now - 7.days - 1.second)

    expect(ranked.first.recent_mountain_count).to eq(1)
  end

  it "counts a new saved rating on an older mountain as recent activity" do
    race = contested_race
    voter = create(:voter)
    create(:voter_race_baseline, race: race, voter: voter, updated_at: old_time)
    create(:rating, candidacy: race.candidacies.first, voter: voter, updated_at: now - 7.days)

    expect(ranked.first.recent_mountain_count).to eq(1)
  end

  it "does not use unsaved drafts, ratings without a saved mountain, or private engagements as popularity" do
    race = contested_race
    create(:mountain_draft, race: race)
    create(:rating, candidacy: race.candidacies.first, updated_at: now)
    create(:engagement, engageable: race, kind: "bookmark")
    create(:engagement, engageable: race, kind: "hide")

    expect(ranked.first).to have_attributes(saved_mountain_count: 0, recent_mountain_count: 0)
  end

  it "boosts federal offices and governors, while leaving state legislators at the ordinary score" do
    jurisdiction = create(:jurisdiction, :state)
    local = contested_race
    state_senator = contested_race(office: create(:office, jurisdiction: jurisdiction,
      position: create(:position, :senator, title: "State Senator", entity_code: "POSITION-STATE_SENATOR")),
      election: create(:election, jurisdiction: jurisdiction))
    governor = contested_race(office: create(:office, jurisdiction: jurisdiction,
      position: create(:position, :governor, entity_code: "POSITION-GOVERNOR")),
      election: create(:election, jurisdiction: jurisdiction))
    federal = contested_race(office: create(:office, jurisdiction: jurisdiction,
      position: create(:position, :senator, entity_code: "POSITION-SENATOR")),
      election: create(:election, jurisdiction: jurisdiction))

    expect(ranked.map(&:id)).to eq([ governor.id, federal.id, local.id, state_senator.id ])
    expect(ranked.map(&:nationally_prominent)).to eq([ true, true, false, false ])
  end

  it "keeps equal scores in a stable order even when the incoming scope has another ordering" do
    races = Array.new(3) { contested_race }
    results = described_class.new(Race.active.order(id: :desc), now: now).races

    expect(results.map(&:id)).to eq(races.map(&:id))
  end
end

require "rails_helper"

# Results add up saved mountains for one group, residents or visitors, and never mix the two. The same
# mountains give an approval count and a first-choice (plurality) count, from the first saved mountain.
RSpec.describe RaceResults do
  let(:race) { create(:race, :active) }
  let(:ventura_quinn) { create(:candidacy, race: race, citizen: create(:citizen, first_name: "Marisol", last_name: "Ventura-Quinn")) }
  let(:okafor) { create(:candidacy, race: race, citizen: create(:citizen, first_name: "Dana", last_name: "Okafor")) }
  let(:lindqvist) { create(:candidacy, race: race, citizen: create(:citizen, first_name: "Theo", last_name: "Lindqvist")) }
  let(:feld) do
    create(:candidacy, race: race, citizen: create(:citizen, first_name: "Jonah", last_name: "Feld"), participation: "off_ballot", primary_candidacy: create(:candidacy))
  end

  # One saved mountain: a baseline of 250 and the given ratings.
  def mountain!(ratings, counted_as: "resident", include_primaries: false)
    voter = create(:voter)
    VoterRaceBaseline.create!(voter: voter, race: race, baseline: 250, counted_as: counted_as)
    VoterRacePreference.create!(voter: voter, race: race, include_primary_candidates: true) if include_primaries
    ratings.each { |candidacy, rating| Rating.create!(voter: voter, candidacy: candidacy, rating: rating) }
  end

  before do
    # Ten residents. Okafor is everyone's acceptable choice, but few rate her highest.
    4.times { mountain!({ ventura_quinn => 450, okafor => 300, lindqvist => 100 }) }
    3.times { mountain!({ lindqvist => 400, okafor => 300, ventura_quinn => 50, feld => 400 }, include_primaries: true) }
    2.times { mountain!({ okafor => 400, ventura_quinn => 200, lindqvist => 200 }) }
    mountain!({ ventura_quinn => 300, okafor => 300, lindqvist => 0 })
    # Two visitors trying a pretend vote.
    2.times { mountain!({ lindqvist => 500 }, counted_as: "visitor") }
  end

  let(:residents) { described_class.new(race) }

  it "shows approval and first choice from the same residents' mountains, splitting a tie" do
    expect(residents.mountain_count).to eq(10)
    expect(residents.approval_shares).to eq(ventura_quinn.id => 50.0, okafor.id => 100.0, lindqvist.id => 30.0)
    expect(residents.first_choice_shares).to eq(ventura_quinn.id => 45.0, lindqvist.id => 30.0, okafor.id => 25.0)
  end

  it "summarizes how residents approve" do
    expect(residents.average_approvals).to eq(1.8)
    expect(residents.multiple_approval_share).to eq(80.0)
    expect(residents.median_baseline).to eq(250)
  end

  it "shows how often approving one candidate goes with approving another" do
    expect(residents.shared_support).to include(
      [ ventura_quinn.id, okafor.id ] => 100.0, [ okafor.id, ventura_quinn.id ] => 50.0,
      [ okafor.id, lindqvist.id ] => 30.0, [ lindqvist.id, okafor.id ] => 100.0
    )
    expect(residents.shared_support).not_to have_key([ ventura_quinn.id, lindqvist.id ])
  end

  it "bands each candidate's ratings in 50-point steps" do
    expect(residents.rating_distribution.select { |(candidacy_id, _), _| candidacy_id == lindqvist.id })
      .to eq([ lindqvist.id, 0 ] => 1, [ lindqvist.id, 2 ] => 4, [ lindqvist.id, 4 ] => 2, [ lindqvist.id, 8 ] => 3)
  end

  it "counts the off-ballot tally among only the residents who include primary candidates, however few" do
    expect(residents.off_ballot).to eq(mountain_count: 3, approval_shares: { feld.id => 100.0 })
  end

  it "keeps visitors' pretend votes out of residents' results, showing even a small group" do
    visitors = described_class.new(race, group: "visitor")

    expect(visitors.summary).to include(mountain_count: 2, any_mountains: true, approval_shares: include(lindqvist.id => 100.0))
    expect(residents.summary).to include(any_mountains: true, approval_shares: residents.approval_shares)
    expect(described_class.new(create(:race)).summary).to eq(group: "resident", mountain_count: 0, any_mountains: false)
  end

  it "still counts every saved mountain, residents and visitors, for the race's overall tally" do
    expect(race.aggregate_votes.transform_keys(&:id)).to eq(ventura_quinn.id => 5, okafor.id => 10, lindqvist.id => 5, feld.id => 3)
  end
end

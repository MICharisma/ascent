require 'rails_helper'

RSpec.describe Race, type: :model do
  it 'keeps approval thresholds and archive history separate within one Election' do
    election = create(:election)
    mayor = create(:race, election: election)
    council = create(:race, election: election)
    voter = create(:voter)
    mayor_candidate = create(:candidacy, race: mayor)
    council_candidate = create(:candidacy, race: council)
    mayor_baseline = create(:voter_race_baseline, voter: voter, race: mayor, baseline: 200)
    council_baseline = create(:voter_race_baseline, voter: voter, race: council, baseline: 350)
    mayor_rating = create(:rating, voter: voter, candidacy: mayor_candidate, rating: 300)
    council_rating = create(:rating, voter: voter, candidacy: council_candidate, rating: 300)

    expect(mayor_rating).to be_approved
    expect(council_rating).not_to be_approved
    expect(mayor.approval_winner).to eq(mayor_candidate)
    expect(council.approval_winner).to be_nil
    expect(Rating.for_election(election)).to contain_exactly(mayor_rating, council_rating)
    expect(Rating.for_race(mayor)).to contain_exactly(mayor_rating)

    mayor_baseline.update!(baseline: 300)
    expect(mayor.approval_winner).to be_nil
    expect(council_baseline.reload.baseline).to eq(350)
    expect(voter.voter_race_baseline_archives.pluck(:race_id)).to eq([ mayor.id ])
  end

  it 'rejects an Office outside the election\'s jurisdiction' do
    race = build(:race, election: create(:election), office: create(:office))

    expect(race).not_to be_valid
    expect(race.errors[:office]).to include("must be within the election's jurisdiction")
  end

  # A state primary decides its districts' nominations on the same day.
  it 'accepts an Office in a jurisdiction nested within the election\'s' do
    state = create(:jurisdiction)
    district = create(:jurisdiction, parent: state)
    race = build(:race, election: create(:election, jurisdiction: state), office: create(:office, jurisdiction: district))

    expect(race).to be_valid
  end

  it 'prevents jurisdiction changes from invalidating existing Races' do
    race = create(:race)
    other_jurisdiction = create(:jurisdiction)

    expect(race.election.update(jurisdiction: other_jurisdiction)).to be(false)
    expect(race.election.errors[:jurisdiction]).to be_present
    expect(race.office.update(jurisdiction: other_jurisdiction)).to be(false)
    expect(race.office.errors[:jurisdiction]).to be_present
  end

  it 'accepts opinions without claiming that the voter belongs to the electorate' do
    race = create(:race)
    voter = create(:voter)
    create(:residence, voter: voter, jurisdiction: create(:jurisdiction))
    candidacy = create(:candidacy, race: race)

    expect(build(:rating, voter: voter, candidacy: candidacy)).to be_valid
    expect(voter.current_residence.jurisdiction).not_to eq(race.election.jurisdiction)
  end

  it 'resolves an Office holder through the most recent completed Race' do
    office = create(:office)
    election = create(:election, :completed, jurisdiction: office.jurisdiction)
    race = create(:race, :completed, election: election, office: office)
    candidacy = create(:candidacy, race: race)
    voter = create(:voter)
    create(:voter_race_baseline, voter: voter, race: race, baseline: 200)
    create(:rating, voter: voter, candidacy: candidacy, rating: 400)

    expect(office.current_office_holder).to eq(candidacy)
    expect(candidacy.election).to eq(election)
    expect(candidacy.citizen.elections).to contain_exactly(election)
    expect(Citizen.with_recent_candidacies).to include(candidacy.citizen)
    expect(Voter.with_voting_activity.find(voter.id).ratings).to be_present
  end

  it 'cleans up a deleted Race without deleting its Election or sibling Races' do
    election = create(:election)
    race = create(:race, election: election)
    sibling = create(:race, election: election)
    voter = create(:voter)
    candidacy = create(:candidacy, race: race)
    create(:rating, voter: voter, candidacy: candidacy)
    create(:voter_race_baseline, voter: voter, race: race)
    race.voter_race_baseline_archives.load

    race.destroy!

    expect(Election.exists?(election.id)).to be(true)
    expect(Race.exists?(sibling.id)).to be(true)
    expect(Candidacy.exists?(candidacy.id)).to be(false)
    expect(VoterRaceBaselineArchive.where(race_id: race.id)).to be_empty
  end
end

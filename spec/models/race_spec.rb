require 'rails_helper'

RSpec.describe Race, type: :model do
  describe 'validations' do
    subject { build(:race) }

    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[upcoming active completed cancelled]) }
  end

  describe 'associations' do
    it { should belong_to(:office) }
    it { should belong_to(:election) }
    it { should have_many(:candidacies).dependent(:destroy) }
    it { should have_many(:candidates).through(:candidacies) }
    it { should have_many(:voter_race_baselines).dependent(:destroy) }
  end

  describe 'scopes' do
    let!(:upcoming_race) { create(:race, status: 'upcoming') }
    let!(:active_race) { create(:race, status: 'active') }
    let!(:completed_race) { create(:race, status: 'completed') }
    let!(:mock_race) { create(:race, :mock) }

    it '.upcoming returns upcoming races' do
      expect(Race.upcoming).to include(upcoming_race)
      expect(Race.upcoming).not_to include(active_race)
    end

    it '.active returns active races' do
      expect(Race.active).to include(active_race)
      expect(Race.active).not_to include(upcoming_race)
    end

    it '.completed returns completed races' do
      expect(Race.completed).to include(completed_race)
      expect(Race.completed).not_to include(upcoming_race)
    end

    it '.mock returns mock races' do
      expect(Race.mock).to include(mock_race)
    end
  end

  describe '#aggregate_votes' do
    let(:race) { create(:race) }
    let!(:candidacy1) { create(:candidacy, race: race) }
    let!(:candidacy2) { create(:candidacy, race: race) }
    let!(:candidacy3) { create(:candidacy, race: race) }

    context 'with no voters or ratings' do
      it 'returns all candidacies with zero votes' do
        results = race.aggregate_votes

        expect(results).to be_a(Hash)
        expect(results.keys).to match_array([ candidacy1, candidacy2, candidacy3 ])
        expect(results.values).to all(eq(0))
      end
    end

    context 'with voters and ratings' do
      let!(:voter1) { create(:voter) }
      let!(:voter2) { create(:voter) }
      let!(:voter3) { create(:voter) }

      # Set baselines
      let!(:baseline1) { create(:voter_race_baseline, voter: voter1, race: race, baseline: 250) }
      let!(:baseline2) { create(:voter_race_baseline, voter: voter2, race: race, baseline: 300) }
      let!(:baseline3) { create(:voter_race_baseline, voter: voter3, race: race, baseline: 200) }

      before do
        # Voter 1 ratings (baseline: 250)
        create(:rating, voter: voter1, candidacy: candidacy1, rating: 400) # Above baseline - COUNTS
        create(:rating, voter: voter1, candidacy: candidacy2, rating: 200) # Below baseline - doesn't count
        create(:rating, voter: voter1, candidacy: candidacy3, rating: 250) # At baseline - does not count

        # Voter 2 ratings (baseline: 300)
        create(:rating, voter: voter2, candidacy: candidacy1, rating: 350) # Above baseline - COUNTS
        create(:rating, voter: voter2, candidacy: candidacy2, rating: 280) # Below baseline - doesn't count
        create(:rating, voter: voter2, candidacy: candidacy3, rating: 100) # Below baseline - doesn't count

        # Voter 3 ratings (baseline: 200)
        create(:rating, voter: voter3, candidacy: candidacy1, rating: 150) # Below baseline - doesn't count
        create(:rating, voter: voter3, candidacy: candidacy2, rating: 450) # Above baseline - COUNTS
        create(:rating, voter: voter3, candidacy: candidacy3, rating: 300) # Above baseline - COUNTS
      end

      it 'correctly counts approval votes based on individual baselines' do
        results = race.aggregate_votes

        expect(results[candidacy1]).to eq(2) # voter1(400>250) + voter2(350>300)
        expect(results[candidacy2]).to eq(1) # voter3(450>200)
        expect(results[candidacy3]).to eq(1) # voter3(300>200)
      end

      it 'includes all candidacies even if they have no approval votes' do
        # Remove all ratings for candidacy2 that would count
        Rating.where(candidacy: candidacy2, voter: voter3).update_all(rating: 150)

        results = race.aggregate_votes
        expect(results.keys).to include(candidacy2)
        expect(results[candidacy2]).to eq(0)
      end
    end

    context 'with voters who have no ratings' do
      let!(:voter) { create(:voter) }
      let!(:baseline) { create(:voter_race_baseline, voter: voter, race: race, baseline: 250) }

      it 'does not affect vote counts' do
        results = race.aggregate_votes
        expect(results.values).to all(eq(0))
      end
    end

    context 'with ratings but no baselines' do
      let!(:voter) { create(:voter) }

      before do
        create(:rating, voter: voter, candidacy: candidacy1, rating: 400)
      end

      it 'returns zero votes for all candidacies' do
        results = race.aggregate_votes
        expect(results.values).to all(eq(0))
      end
    end
  end

  describe '#approval_results' do
    let(:race) { create(:race) }
    let!(:candidacy1) { create(:candidacy, race: race) }
    let!(:candidacy2) { create(:candidacy, race: race) }
    let!(:candidacy3) { create(:candidacy, race: race) }

    before do
      # Mock aggregate_votes to return known results
      allow(race).to receive(:aggregate_votes).and_return({
        candidacy1 => 5,
        candidacy2 => 10,
        candidacy3 => 3
      })
    end

    it 'returns candidacies sorted by vote count descending' do
      results = race.approval_results

      expect(results).to be_an(Array)
      expect(results.map(&:first)).to eq([ candidacy2, candidacy1, candidacy3 ])
      expect(results.map(&:second)).to eq([ 10, 5, 3 ])
    end
  end

  describe '#approval_winner' do
    let(:race) { create(:race) }
    let!(:candidacy1) { create(:candidacy, race: race) }
    let!(:candidacy2) { create(:candidacy, race: race) }

    context 'with clear winner' do
      before do
        allow(race).to receive(:aggregate_votes).and_return({
          candidacy1 => 3,
          candidacy2 => 7
        })
      end

      it 'returns the candidacy with most votes' do
        expect(race.approval_winner).to eq(candidacy2)
      end
    end

    context 'with tie' do
      before do
        allow(race).to receive(:aggregate_votes).and_return({
          candidacy1 => 5,
          candidacy2 => 5
        })
      end

      it 'returns one of the tied candidacies' do
        winner = race.approval_winner
        expect([ candidacy1, candidacy2 ]).to include(winner)
      end
    end

    context 'with no votes' do
      before do
        allow(race).to receive(:aggregate_votes).and_return({
          candidacy1 => 0,
          candidacy2 => 0
        })
      end

      it 'returns nil' do
        expect(race.approval_winner).to be_nil
      end
    end

    context 'with empty race' do
      before do
        allow(race).to receive(:aggregate_votes).and_return({})
      end

      it 'returns nil' do
        expect(race.approval_winner).to be_nil
      end
    end
  end

  describe '#results_summary' do
    let(:race) { create(:race) }
    let!(:candidacy1) { create(:candidacy, race: race) }
    let!(:candidacy2) { create(:candidacy, race: race) }
    let!(:voter1) { create(:voter) }
    let!(:voter2) { create(:voter) }

    before do
      create(:voter_race_baseline, voter: voter1, race: race, baseline: 250)
      create(:voter_race_baseline, voter: voter2, race: race, baseline: 300)

      allow(race).to receive(:aggregate_votes).and_return({
        candidacy1 => 3,
        candidacy2 => 7
      })
      allow(race).to receive(:approval_winner).and_return(candidacy2)
      allow(candidacy2.citizen).to receive(:name).and_return("Jane Smith")
    end

    it 'returns comprehensive race statistics' do
      summary = race.results_summary

      expect(summary).to include(
        total_candidacies: 2,
        total_registered_voters: 2,
        total_approval_votes: 10,
        average_approvals_per_voter: 5.0,
        winner: "Jane Smith",
        winning_vote_count: 7
      )
    end

    context 'with no voters' do
      before do
        VoterRaceBaseline.where(race: race).destroy_all
      end

      it 'handles division by zero gracefully' do
        summary = race.results_summary
        expect(summary[:average_approvals_per_voter]).to eq(0)
      end
    end
  end

  describe '#result_for' do
    let(:race) { create(:race) }
    let!(:candidacy1) { create(:candidacy, race: race) }
    let!(:candidacy2) { create(:candidacy, race: race) }
    let!(:candidacy3) { create(:candidacy, race: race) }

    context 'with mock aggregate_votes results' do
      before do
        allow(race).to receive(:aggregate_votes).and_return({
          candidacy1 => 15,
          candidacy2 => 7,
          candidacy3 => 0
        })
      end

      it 'returns the correct vote count for each candidacy' do
        expect(race.result_for(candidacy1)).to eq(15)
        expect(race.result_for(candidacy2)).to eq(7)
        expect(race.result_for(candidacy3)).to eq(0)
      end

      it 'works with reloaded candidacy objects' do
        reloaded_candidacy = Candidacy.find(candidacy1.id)
        expect(race.result_for(reloaded_candidacy)).to eq(15)
      end
    end

    context 'with candidacy not in race' do
      let(:other_race) { create(:race) }
      let!(:external_candidacy) { create(:candidacy, race: other_race) }

      before do
        allow(race).to receive(:aggregate_votes).and_return({
          candidacy1 => 5
        })
      end

      it 'returns 0 for candidacy not in this race' do
        expect(race.result_for(external_candidacy)).to eq(0)
      end
    end

    context 'with real vote aggregation' do
      let!(:voter1) { create(:voter) }
      let!(:voter2) { create(:voter) }

      before do
        # Set up baselines
        create(:voter_race_baseline, voter: voter1, race: race, baseline: 250)
        create(:voter_race_baseline, voter: voter2, race: race, baseline: 300)

        # Voter 1 ratings (baseline: 250)
        create(:rating, voter: voter1, candidacy: candidacy1, rating: 400) # Above baseline - COUNTS
        create(:rating, voter: voter1, candidacy: candidacy2, rating: 200) # Below baseline - doesn't count

        # Voter 2 ratings (baseline: 300)
        create(:rating, voter: voter2, candidacy: candidacy1, rating: 350) # Above baseline - COUNTS
        create(:rating, voter: voter2, candidacy: candidacy2, rating: 280) # Below baseline - doesn't count
      end

      it 'returns correct approval vote counts from real data' do
        expect(race.result_for(candidacy1)).to eq(2) # Both voters approved
        expect(race.result_for(candidacy2)).to eq(0) # No approvals
        expect(race.result_for(candidacy3)).to eq(0) # No ratings at all
      end

      it 'is consistent with aggregate_votes method' do
        full_results = race.aggregate_votes

        race.candidacies.each do |candidacy|
          expect(race.result_for(candidacy)).to eq(full_results[candidacy])
        end
      end
    end

    context 'edge cases' do
      it 'handles race with no votes gracefully' do
        expect(race.result_for(candidacy1)).to eq(0)
        expect(race.result_for(candidacy2)).to eq(0)
        expect(race.result_for(candidacy3)).to eq(0)
      end
    end
  end
end

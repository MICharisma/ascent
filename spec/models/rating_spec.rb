require 'rails_helper'

RSpec.describe Rating, type: :model do
  describe 'associations' do
    it { should belong_to(:voter) }
    it { should belong_to(:candidacy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:rating) }
    it { should validate_inclusion_of(:rating).in_range(0..500) }

    describe 'uniqueness validation' do
      let(:rating) { create(:rating) }

      it 'validates uniqueness of voter_id scoped to candidacy_id' do
        expect(rating).to validate_uniqueness_of(:voter_id)
          .scoped_to(:candidacy_id)
          .with_message("can only rate each candidacy once")
      end
    end
  end

  describe 'scopes' do
    let!(:high_rating) { create(:rating, rating: 400) }
    let!(:medium_rating) { create(:rating, rating: 250) }
    let!(:low_rating) { create(:rating, rating: 100) }

    describe '.above_baseline' do
      it 'returns ratings strictly above the baseline' do
        expect(Rating.above_baseline(250)).to contain_exactly(high_rating)
      end

      it 'excludes ratings below baseline' do
        expect(Rating.above_baseline(250)).not_to include(low_rating)
      end
    end

    describe '.below_baseline' do
      it 'returns ratings at or below the baseline' do
        expect(Rating.below_baseline(250)).to contain_exactly(medium_rating, low_rating)
      end

      it 'excludes ratings strictly above the baseline' do
        expect(Rating.below_baseline(250)).not_to include(high_rating)
      end
    end

    describe '.for_election' do
      let(:election1) { create(:election) }
      let(:election2) { create(:election) }
      let(:candidacy1) { create(:candidacy, race: create(:race, election: election1)) }
      let(:candidacy2) { create(:candidacy, race: create(:race, election: election2)) }
      let!(:rating1) { create(:rating, candidacy: candidacy1) }
      let!(:rating2) { create(:rating, candidacy: candidacy2) }

      it 'returns ratings for candidacies in the specified election' do
        expect(Rating.for_election(election1)).to contain_exactly(rating1)
      end
    end

    describe '.for_voter_in_election' do
      let(:voter1) { create(:voter) }
      let(:voter2) { create(:voter) }
      let(:election) { create(:election) }
      let(:candidacy1) { create(:candidacy, race: create(:race, election: election)) }
      let(:candidacy2) { create(:candidacy, race: create(:race, election: election)) }
      let!(:rating1) { create(:rating, voter: voter1, candidacy: candidacy1) }
      let!(:rating2) { create(:rating, voter: voter1, candidacy: candidacy2) }
      let!(:rating3) { create(:rating, voter: voter2, candidacy: candidacy1) }

      it 'returns ratings for specific voter in specific election' do
        expect(Rating.for_voter_in_election(voter1, election)).to contain_exactly(rating1, rating2)
      end
    end
  end

  describe 'callbacks' do
    describe '#archive_previous_rating (before_update)' do
      let(:rating) { create(:rating, rating: 300) }

      context 'when rating value changes' do
        it 'creates a rating archive' do
          expect {
            rating.update(rating: 400)
          }.to change(RatingArchive, :count).by(1)
        end

        it 'archives the previous rating value' do
          rating.update(rating: 400)
          archive = RatingArchive.last

          expect(archive.voter).to eq(rating.voter)
          expect(archive.candidacy).to eq(rating.candidacy)
          expect(archive.rating).to eq(300) # Previous value
          expect(archive.reason).to eq("Updated rating: 300 → 400")
        end
      end

      context 'when rating value does not change' do
        it 'does not create a rating archive' do
          expect {
            rating.update(created_at: 1.hour.ago)
          }.not_to change(RatingArchive, :count)
        end
      end

      context 'when creating new rating' do
        it 'does not create a rating archive' do
          expect {
            create(:rating)
          }.not_to change(RatingArchive, :count)
        end
      end
    end
  end

  describe 'instance methods' do
    let(:voter) { create(:voter, first_name: "John", last_name: "Doe") }
    let(:citizen) { create(:citizen, first_name: "Jane", middle_name: nil, last_name: "Smith") }
    let(:candidacy) { create(:candidacy, citizen: citizen) }
    let(:rating) { create(:rating, voter: voter, candidacy: candidacy, rating: 350) }

    describe '#name' do
      it 'combines voter name and candidate name' do
        expect(rating.name).to eq("John Doe rating for Jane Smith")
      end
    end

    describe '#rating_percentage' do
      it 'converts rating to percentage (0-500 -> 0-100%)' do
        expect(rating.rating_percentage).to eq(70.0) # 350/500 * 100 = 70%
      end

      context 'with minimum rating' do
        let(:min_rating) { create(:rating, rating: 0) }

        it 'returns 0%' do
          expect(min_rating.rating_percentage).to eq(0.0)
        end
      end

      context 'with maximum rating' do
        let(:max_rating) { create(:rating, rating: 500) }

        it 'returns 100%' do
          expect(max_rating.rating_percentage).to eq(100.0)
        end
      end

      context 'with decimal result' do
        let(:decimal_rating) { create(:rating, rating: 333) }

        it 'rounds to 1 decimal place' do
          expect(decimal_rating.rating_percentage).to eq(66.6) # 333/500 * 100 = 66.6%
        end
      end
    end

    describe '#approved?' do
      let(:race) { candidacy.race }
      let!(:baseline) { create(:voter_race_baseline, voter: voter, race: race, baseline: 300) }

      context 'with rating above baseline' do
        it 'returns true' do
          expect(rating.approved?).to be true # 350 >= 300
        end
      end

      context 'with rating at baseline' do
        let(:rating) { create(:rating, voter: voter, candidacy: candidacy, rating: 300) }

        it 'returns false' do
          expect(rating.approved?).to be false # 300 does not exceed 300
        end
      end

      context 'with rating below baseline' do
        let(:rating) { create(:rating, voter: voter, candidacy: candidacy, rating: 250) }

        it 'returns false' do
          expect(rating.approved?).to be false # 250 < 300
        end
      end

      context 'with explicit baseline parameter' do
        it 'uses provided baseline instead of voter baseline' do
          expect(rating.approved?(400)).to be false # 350 < 400
          expect(rating.approved?(300)).to be true  # 350 >= 300
        end
      end

      context 'with no voter baseline for election' do
        before { baseline.destroy }

        it 'returns false when no baseline found' do
          expect(rating.approved?).to be false
        end
      end
    end

    describe '#voter_baseline_for_race' do
      let(:race) { candidacy.race }
      let!(:baseline) { create(:voter_race_baseline, voter: voter, race: race, baseline: 275) }

      it 'returns the voter baseline for the candidacy election' do
        expect(rating.voter_baseline_for_race).to eq(275)
      end

      context 'with no baseline for election' do
        before { baseline.destroy }

        it 'returns nil' do
          expect(rating.voter_baseline_for_race).to be_nil
        end
      end

      context 'with baseline for different election' do
        let(:other_race) { create(:race) }
        before do
          baseline.update(race: other_race)
        end

        it 'returns nil' do
          expect(rating.voter_baseline_for_race).to be_nil
        end
      end
    end
  end

  describe 'edge cases' do
    describe 'boundary rating values' do
      it 'accepts minimum rating value (0)' do
        rating = build(:rating, rating: 0)
        expect(rating).to be_valid
      end

      it 'accepts maximum rating value (500)' do
        rating = build(:rating, rating: 500)
        expect(rating).to be_valid
      end

      it 'rejects rating below minimum' do
        rating = build(:rating, rating: -1)
        expect(rating).not_to be_valid
      end

      it 'rejects rating above maximum' do
        rating = build(:rating, rating: 501)
        expect(rating).not_to be_valid
      end
    end

    describe 'duplicate rating prevention' do
      let(:existing_rating) { create(:rating) }

      it 'prevents voter from rating same candidacy twice' do
        duplicate_rating = build(:rating,
          voter: existing_rating.voter,
          candidacy: existing_rating.candidacy,
          rating: 400
        )

        expect(duplicate_rating).not_to be_valid
        expect(duplicate_rating.errors[:voter_id]).to include("can only rate each candidacy once")
      end

      it 'allows same voter to rate different candidacies' do
        different_candidacy = create(:candidacy)
        new_rating = build(:rating,
          voter: existing_rating.voter,
          candidacy: different_candidacy
        )

        expect(new_rating).to be_valid
      end

      it 'allows different voters to rate same candidacy' do
        different_voter = create(:voter)
        new_rating = build(:rating,
          voter: different_voter,
          candidacy: existing_rating.candidacy
        )

        expect(new_rating).to be_valid
      end
    end
  end
end

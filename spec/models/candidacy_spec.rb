require 'rails_helper'

RSpec.describe Candidacy, type: :model do
  describe 'associations' do
    it { should belong_to(:citizen) }
    it { should belong_to(:race) }
    it { should have_many(:ratings).dependent(:destroy) }
    it { should have_many(:rating_archives).dependent(:destroy) }
    it { should have_many(:stances).dependent(:destroy) }
    it { should have_many(:voters).through(:ratings) }
  end

  describe 'validations' do
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[announced active withdrawn disqualified]) }
  end

  describe 'scopes' do
    let!(:announced_candidacy) { create(:candidacy, status: 'announced') }
    let!(:active_candidacy) { create(:candidacy, status: 'active') }
    let!(:withdrawn_candidacy) { create(:candidacy, status: 'withdrawn') }
    let!(:disqualified_candidacy) { create(:candidacy, status: 'disqualified') }

    describe '.announced' do
      it 'returns only announced candidacies' do
        expect(Candidacy.announced).to contain_exactly(announced_candidacy)
      end
    end

    describe '.active' do
      it 'returns only active candidacies' do
        expect(Candidacy.active).to contain_exactly(active_candidacy)
      end
    end

    describe '.withdrawn' do
      it 'returns only withdrawn candidacies' do
        expect(Candidacy.withdrawn).to contain_exactly(withdrawn_candidacy)
      end
    end

    describe '.disqualified' do
      it 'returns only disqualified candidacies' do
        expect(Candidacy.disqualified).to contain_exactly(disqualified_candidacy)
      end
    end

    describe '.with_rating_details' do
      it 'includes citizen and ratings' do
        expect(Candidacy.with_rating_details.includes_values).to include(:citizen, :ratings)
      end
    end

    describe '.with_election_context' do
      it 'includes election, office, and position details' do
        expect(Candidacy.with_election_context.includes_values).to include(race: [ :election, { office: :position } ])
      end
    end
  end

  describe 'instance methods' do
    let(:citizen) { create(:citizen, first_name: "John", middle_name: nil, last_name: "Smith") }
    let(:position) { create(:position, title: "Mayor") }
    let(:office) { create(:office, position: position) }
    let(:race) { create(:race, office: office, election: create(:election, jurisdiction: office.jurisdiction)) }
    let(:candidacy) { create(:candidacy, citizen: citizen, race: race) }

    describe '#name' do
      it 'combines citizen name with office position title' do
        expect(candidacy.name).to eq("John Smith for Mayor")
      end
    end

    describe '#average_rating' do
      context 'with no ratings' do
        it 'returns nil' do
          expect(candidacy.average_rating).to be_nil
        end
      end

      context 'with ratings' do
        let!(:rating1) { create(:rating, candidacy: candidacy, rating: 300) }
        let!(:rating2) { create(:rating, candidacy: candidacy, rating: 400) }
        let!(:rating3) { create(:rating, candidacy: candidacy, rating: 200) }

        it 'returns the average rating rounded to 1 decimal place' do
          expect(candidacy.average_rating).to eq(300.0)
        end
      end

      context 'with decimal average' do
        let!(:rating1) { create(:rating, candidacy: candidacy, rating: 333) }
        let!(:rating2) { create(:rating, candidacy: candidacy, rating: 334) }

        it 'rounds to 1 decimal place' do
          expect(candidacy.average_rating).to eq(333.5)
        end
      end
    end

    describe '#approval_count' do
      let!(:rating1) { create(:rating, candidacy: candidacy, rating: 300) }
      let!(:rating2) { create(:rating, candidacy: candidacy, rating: 400) }
      let!(:rating3) { create(:rating, candidacy: candidacy, rating: 200) }

      context 'with no baseline provided' do
        it 'returns 0' do
          expect(candidacy.approval_count(nil)).to eq(0)
        end
      end

      context 'with baseline of 250' do
        it 'counts ratings strictly above baseline' do
          expect(candidacy.approval_count(250)).to eq(2) # 300 and 400 are > 250
        end
      end

      context 'with baseline of 350' do
        it 'counts only ratings above baseline' do
          expect(candidacy.approval_count(350)).to eq(1) # Only 400 is > 350
        end
      end

      context 'with baseline higher than all ratings' do
        it 'returns 0' do
          expect(candidacy.approval_count(500)).to eq(0)
        end
      end
    end

    describe '#approval_percentage' do
      let!(:rating1) { create(:rating, candidacy: candidacy, rating: 300) }
      let!(:rating2) { create(:rating, candidacy: candidacy, rating: 400) }
      let!(:rating3) { create(:rating, candidacy: candidacy, rating: 200) }
      let!(:rating4) { create(:rating, candidacy: candidacy, rating: 100) }

      context 'with no baseline provided' do
        it 'returns 0' do
          expect(candidacy.approval_percentage(nil)).to eq(0)
        end
      end

      context 'with no ratings' do
        let(:candidacy_no_ratings) { create(:candidacy) }

        it 'returns 0' do
          expect(candidacy_no_ratings.approval_percentage(250)).to eq(0)
        end
      end

      context 'with baseline of 250' do
        it 'calculates percentage of approving ratings' do
          # 2 out of 4 ratings are > 250 (300, 400)
          expect(candidacy.approval_percentage(250)).to eq(50.0)
        end
      end

      context 'with baseline of 350' do
        it 'calculates percentage correctly' do
          # 1 out of 4 ratings is > 350 (400)
          expect(candidacy.approval_percentage(350)).to eq(25.0)
        end
      end

      context 'with baseline where all ratings approve' do
        it 'returns 100%' do
          expect(candidacy.approval_percentage(50)).to eq(100.0)
        end
      end

      context 'with fractional percentage' do
        let!(:rating5) { create(:rating, candidacy: candidacy, rating: 250) }

        it 'rounds to 1 decimal place' do
          # 2 out of 5 ratings are > 250 = 40%
          expect(candidacy.approval_percentage(250)).to eq(40.0)
        end
      end
    end
  end

  describe 'status transitions' do
    let(:candidacy) { create(:candidacy, status: 'announced') }

    it 'can transition from announced to active' do
      candidacy.update(status: 'active')
      expect(candidacy.status).to eq('active')
    end

    it 'can transition from active to withdrawn' do
      candidacy.update(status: 'active')
      candidacy.update(status: 'withdrawn')
      expect(candidacy.status).to eq('withdrawn')
    end

    it 'can transition from any status to disqualified' do
      candidacy.update(status: 'disqualified')
      expect(candidacy.status).to eq('disqualified')
    end
  end

  describe 'announcement date validation' do
    it 'allows a missing announcement date, which ballot sources do not publish' do
      expect(build(:candidacy, announcement_date: nil)).to be_valid
    end

    it 'accepts valid announcement date' do
      candidacy = build(:candidacy, announcement_date: 1.month.ago)
      expect(candidacy).to be_valid
    end
  end
end

require 'rails_helper'

RSpec.describe Voter, type: :model do
  describe 'associations' do
    it { should have_many(:residences).dependent(:destroy) }
    it { should have_many(:jurisdictions).through(:residences) }
    it { should have_many(:ratings).dependent(:destroy) }
    it { should have_many(:voter_race_baselines).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:first_name) }
    it { should validate_presence_of(:last_name) }
    it { should validate_presence_of(:email) }
    it 'rejects an email address already used with different capitalization' do
      existing = create(:voter, email: 'erin.brooks@example.test')
      duplicate = build(:voter, email: existing.email.upcase)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to include('has already been taken')
    end
  end

  describe 'devise modules' do
    it 'includes database_authenticatable' do
      expect(Voter.devise_modules).to include(:database_authenticatable)
    end

    it 'includes confirmable' do
      expect(Voter.devise_modules).to include(:confirmable)
    end

    it 'includes registerable' do
      expect(Voter.devise_modules).to include(:registerable)
    end

    it 'includes recoverable' do
      expect(Voter.devise_modules).to include(:recoverable)
    end

    it 'includes rememberable' do
      expect(Voter.devise_modules).to include(:rememberable)
    end

    it 'includes validatable' do
      expect(Voter.devise_modules).to include(:validatable)
    end

    it 'includes trackable' do
      expect(Voter.devise_modules).to include(:trackable)
    end
  end

  describe 'scopes' do
    describe '.with_voting_activity' do
      it 'includes ratings, baselines, and election details' do
        expect(Voter.with_voting_activity.includes_values).to include(:ratings, :voter_race_baselines)
      end
    end

    describe '.with_residence_details' do
      it 'includes residence and jurisdiction information' do
        expect(Voter.with_residence_details.includes_values).to include(residences: :jurisdiction)
      end
    end
  end

  describe 'instance methods' do
    let(:voter) { create(:voter, first_name: "Sarah", last_name: "Johnson") }

    describe '#full_name' do
      it 'combines first and last name' do
        expect(voter.full_name).to eq("Sarah Johnson")
      end

      context 'with missing first name' do
        let(:voter) { build(:voter, first_name: nil, last_name: "Johnson") }

        it 'handles nil gracefully' do
          expect(voter.full_name).to eq("Johnson")
        end
      end

      context 'with missing last name' do
        let(:voter) { build(:voter, first_name: "Sarah", last_name: nil) }

        it 'handles nil gracefully' do
          expect(voter.full_name).to eq("Sarah")
        end
      end
    end

    describe '#name' do
      it 'delegates to full_name' do
        expect(voter.name).to eq(voter.full_name)
      end
    end

    describe '#current_residence' do
      let!(:old_residence) { create(:residence, voter: voter, status: 'inactive') }
      let!(:current_residence) { create(:residence, voter: voter, status: 'active') }

      it 'returns the active residence' do
        expect(voter.current_residence).to eq(current_residence)
      end

      context 'with no active residence' do
        before { current_residence.update(status: 'inactive') }

        it 'returns nil' do
          expect(voter.current_residence).to be_nil
        end
      end
    end

    describe '#residence_history' do
      let!(:residence1) { create(:residence, voter: voter, status: "inactive", registered_at: 1.year.ago) }
      let!(:residence2) { create(:residence, voter: voter, status: "inactive", registered_at: 6.months.ago) }
      let!(:residence3) { create(:residence, voter: voter, registered_at: 1.month.ago) }

      it 'returns residences ordered by registration date descending' do
        history = voter.residence_history
        expect(history).to eq([ residence3, residence2, residence1 ])
      end
    end
  end
end

require 'rails_helper'

RSpec.describe MountainsController, type: :controller do
  let(:race) { create(:race, :active) }

  # Simulated data is for admins.
  before do
    allow(controller).to receive(:current_voter).and_return(create(:voter, admin: true))
  end

  describe 'GET #index' do
    context 'with no race specified' do
      it 'renders successfully' do
        get :index
        expect(response).to have_http_status(:success)
      end
    end

    context 'with race specified' do
      it 'renders successfully with race parameter' do
        get :index, params: { race_id: race.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'POST #simulate' do
    # Simulated candidates and ratings only ever go in a mock election.
    let(:race) { create(:race, :active, :mock) }

    it 'generates realistic simulation data' do
      expect {
        post :simulate, params: { id: race.id }
      }.to change(Candidacy, :count).by_at_least(3) # More realistic expectation
       .and change(Citizen, :count).by_at_least(1) # Some reuse expected
       .and change(Rating, :count).by_at_least(3) # At least one rating per candidacy
    end

    it 'redirects after simulation' do
      post :simulate, params: { id: race.id }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('mountains')
    end

    it 'creates candidacies with valid party affiliations' do
      post :simulate, params: { id: race.id }

      affiliations = race.candidacies.map(&:ballot_labels)
      expect(affiliations).to all(be_present) # All candidates have party affiliations
      expect(affiliations).to all(be_a(String)) # Valid string values
    end

    it 'creates realistic rating distributions' do
      post :simulate, params: { id: race.id }

      ratings = Rating.where(candidacy: race.candidacies).pluck(:rating)
      expect(ratings.min).to be >= 0
      expect(ratings.max).to be <= 500
      expect(ratings.size).to be >= 3 # Multiple ratings created
    end

    it 'uses SmartFactory for conditional creation' do
      # Verify that SmartFactory is being called for simulation
      expect(SmartFactory).to receive(:create_for_mountain_simulation).at_least(:once)
      post :simulate, params: { id: race.id }
    end
  end

  describe 'GET #show' do
    context 'with existing race data' do
      let!(:candidacies) { create_list(:candidacy, 3, race: race) }
      let!(:ratings) do
        voter = create(:voter)
        candidacies.map do |candidacy|
          create(:rating, voter: voter, candidacy: candidacy, rating: rand(100..400))
        end
      end

      it 'renders successfully with race data' do
        get :show, params: { id: race.id }
        expect(response).to have_http_status(:success)
      end
    end
  end
end

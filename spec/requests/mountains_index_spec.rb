require 'rails_helper'

RSpec.describe "Mountains", type: :request do
  describe "GET /mountains" do
    context "with no active races" do
      let!(:completed_race) { create(:race, :completed) }

      it "renders the empty state" do
        get mountains_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Mountain Visualizations")
        expect(response.body).to include("No active races are ready for the mountain interface.")
      end
    end

    context "with active races" do
      let!(:country) { create(:country, name: "United States") }
      let!(:state) { create(:state, name: "Pennsylvania", country: country) }
      let!(:city) { create(:municipality, :with_jurisdiction, name: "Pittsburgh", state: state) }
      let!(:position) { create(:position, title: "Mayor") }
      let!(:office) { create(:office, position: position, jurisdiction: city.jurisdiction) }
      let!(:year) { create(:year, year: 2026) }
      let!(:active_race) { create_race_for(office, :active, year: year, description: "A live municipal demonstration.", is_mock: true) }

      # An admin also sees the controls for simulated data.
      before { sign_in create(:voter, admin: true) }

      before do
        create_list(:candidacy, 2, race: active_race)
      end

      it "lists active races with action links" do
        get mountains_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(ERB::Util.html_escape(active_race.office.name))
        expect(response.body).to include(ERB::Util.html_escape(active_race.election.name))
        expect(response.body).to include("2 candidates")
        expect(response.body).to include("Mock election")
        expect(response.body).to include("View Mountain")
        expect(response.body).to include("Simulate Data")
        expect(response.body).to include("0 saved mountains")
        expect(response.body).to include("0 voters active in the last 7 days")
      end
    end

    it "paginates the ranked races on the server, including the last page and an out-of-range page" do
      races = Array.new(26) do
        create(:race, :active).tap { create_list(:candidacy, 2, race: it) }
      end
      create(:voter_race_baseline, race: races.last)

      get mountains_path
      page = Nokogiri::HTML(response.body)
      first_page_links = page.css(".mountain-race-title a").map { it["href"] }
      expect(first_page_links.size).to eq(25)
      expect(first_page_links.first).to eq(mountain_path(races.last))
      expect(page.at_css('a[rel="next"]')["href"]).to include("page=2")

      get mountains_path, params: { page: 2 }
      last_page_links = Nokogiri::HTML(response.body).css(".mountain-race-title a").map { it["href"] }
      expect(last_page_links).to eq([ mountain_path(races[-2]) ])
      expect(first_page_links & last_page_links).to be_empty

      get mountains_path, params: { page: 999 }
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).css(".mountain-race-title a").map { it["href"] }).to eq(last_page_links)
    end

    it "respects a voter's hidden races and leaves single-candidate races accessible directly" do
      hidden_race = create(:race, :active)
      create_list(:candidacy, 2, race: hidden_race)
      single_race = create(:race, :active)
      create(:candidacy, race: single_race)
      voter = create(:voter)
      create(:engagement, actor: voter, engageable: hidden_race, kind: "hide")
      sign_in voter

      get mountains_path
      expect(Nokogiri::HTML(response.body).css(".mountain-race-card")).to be_empty

      get mountain_path(single_race)
      expect(response).to have_http_status(:ok)

      sign_out voter
      get mountains_path
      expect(Nokogiri::HTML(response.body).css(".mountain-race-title a").map { it["href"] })
        .to eq([ mountain_path(hidden_race) ])
    end
  end

  describe "GET /mountains/:id" do
    let!(:race) { create(:race, :active) }
    let!(:voter) { create(:voter) }

    before { sign_in voter }

    it "renders the mountain page" do
      get mountain_path(race, voter_id: voter.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(race.office.name))
    end

    it "returns not found when the race does not exist" do
      get mountain_path(SecureRandom.uuid_v7)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /mountains/:id/edit" do
    let!(:race) { create(:race, :active) }
    let!(:voter) { create(:voter) }

    before { sign_in voter }
    let!(:candidacy) { create(:candidacy, :active, race: race) }

    it "renders the editable mountain with the stimulus controller" do
      get edit_mountain_path(race, voter_id: voter.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(race.office.name))
      expect(response.body).to include('data-controller="mountain-editor"')
      expect(response.body).to include("rating-input-#{candidacy.id}")
      expect(response.body).to include("mountain-save-bar")
    end
  end

  describe "GET /mountains/:id remains editable after viewing" do
    let!(:race) { create(:race, :active) }
    let!(:voter) { create(:voter) }

    before { sign_in voter }
    let!(:candidacy) { create(:candidacy, :active, race: race) }
    let!(:rating) { create(:rating, voter: voter, candidacy: candidacy, rating: 300) }

    it "keeps the mountain-editor controller on the show page" do
      get mountain_path(race, voter_id: voter.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="mountain-editor"')
      expect(response.body).to include("mountain-chart editable")
      expect(response.body).to include("mountain-save-bar")
      expect(response.body).to include("Rating: 300")
    end
  end

  describe "PATCH /mountains/:id" do
    let!(:race) { create(:race, :active) }
    let!(:voter) { create(:voter) }

    before { sign_in voter }
    let!(:candidacy_a) { create(:candidacy, :active, race: race) }
    let!(:candidacy_b) { create(:candidacy, :active, race: race) }
    let!(:existing_rating) do
      create(:rating, voter: voter, candidacy: candidacy_a, rating: 100)
    end

    it "creates, updates, and removes ratings and baseline" do
      patch mountain_path(race, voter_id: voter.id), params: {
        baseline: 275,
        ratings: {
          candidacy_a.id => 420,
          candidacy_b.id => 180
        }
      }

      expect(response).to redirect_to(mountain_path(race, voter_id: voter.id))
      expect(flash[:notice]).to eq("Mountain ratings updated.")

      expect(existing_rating.reload.rating).to eq(420)
      expect(Rating.find_by(voter: voter, candidacy: candidacy_b).rating).to eq(180)
      expect(VoterRaceBaseline.find_by(voter: voter, race: race).baseline).to eq(275)

      follow_redirect!
      # After save, mountain must still be editable (not a read-only show page).
      expect(response.body).to include('data-controller="mountain-editor"')
      expect(response.body).to include("mountain-chart editable")
      expect(response.body).to include("mountain-save-bar")
      expect(response.body).to include("Rating: 420")
      expect(response.body).to include("Rating: 180")
      expect(response.body).to include('data-role="baseline-value">275<')
    end

    it "clears a rating when submitted blank" do
      patch mountain_path(race, voter_id: voter.id), params: {
        baseline: 250,
        ratings: {
          candidacy_a.id => ""
        }
      }

      expect(response).to redirect_to(mountain_path(race, voter_id: voter.id))
      expect(Rating.find_by(voter: voter, candidacy: candidacy_a)).to be_nil
    end
  end
end

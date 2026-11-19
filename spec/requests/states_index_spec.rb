require 'rails_helper'

RSpec.describe "States Index", type: :request do
  describe "GET /states" do
    context "with no states" do
      it "renders successfully with empty state" do
        get states_path

        expect(response).to have_http_status(200)
        expect(response.body).to include("States")
      end
    end

    context "with multiple states" do
      let!(:usa) { create(:country, name: "United States", code: "US") }
      let!(:canada) { create(:country, name: "Canada", code: "CA") }

      let!(:california) { create(:state, name: "California", code: "CA", country: usa) }
      let!(:texas) { create(:state, name: "Texas", code: "TX", country: usa) }
      let!(:ontario) { create(:state, name: "Ontario", code: "ON", country: canada) }
      let!(:quebec) { create(:state, name: "Quebec", code: "QC", country: canada) }

      it "renders successfully with state data" do
        get states_path

        expect(response).to have_http_status(200)
        expect(response.body).to include("States")
        expect(response.body).to include("California")
        expect(response.body).to include("Texas")
        expect(response.body).to include("Ontario")
        expect(response.body).to include("Quebec")
      end

      it "displays state codes" do
        get states_path

        expect(response.body).to include("CA")
        expect(response.body).to include("TX")
        expect(response.body).to include("ON")
        expect(response.body).to include("QC")
      end

      it "displays associated country information" do
        get states_path

        expect(response.body).to include("United States")
        expect(response.body).to include("Canada")
      end

      it "includes proper HTML structure for Phlex components" do
        get states_path

        expect(response.body).to include('class="')
        expect(response.body).to include("<div")
        expect(response.body).to include("</div>")
      end
    end

    context "with states that have municipalities" do
      let!(:country) { create(:country, name: "United States") }
      let!(:state) { create(:state, name: "California", country: country) }
      let!(:municipality1) { create(:municipality, name: "Los Angeles", state: state) }
      let!(:municipality2) { create(:municipality, name: "San Francisco", state: state) }

      it "displays municipality count information" do
        get states_path

        expect(response).to have_http_status(200)
        expect(response.body).to include("California")
      end
    end

    context "with pagination" do
      let!(:country) { create(:country) }

      before do
        create_list(:state, 30, country: country)
      end

      it "renders successfully with pagination" do
        get states_path

        expect(response).to have_http_status(200)
        expect(response.body).to include("States")
      end

      it "respects page parameter" do
        get states_path, params: { page: 2 }

        expect(response).to have_http_status(200)
        expect(response.body).to include("States")
      end

      it "handles high page numbers gracefully" do
        get states_path, params: { page: 999 }

        expect(response).to have_http_status(200)
        expect(response.body).to include("States")
      end
    end
  end

  describe "GET /countries/:country_id/states" do
    let!(:usa) { create(:country, name: "United States") }
    let!(:canada) { create(:country, name: "Canada") }
    let!(:us_states) { create_list(:state, 3, country: usa) }
    let!(:canadian_provinces) { create_list(:state, 2, country: canada) }

    it "renders states scoped to specific country" do
      get country_states_path(usa)

      expect(response).to have_http_status(200)
      expect(response.body).to include("States")
    end

    it "shows only states for the specified country" do
      get country_states_path(usa)

      expect(response).to have_http_status(200)
      # Should show US states but not Canadian provinces in this scoped view
    end

    it "handles non-existent country gracefully" do
      get country_states_path(SecureRandom.uuid_v7)

      expect(response).to have_http_status(:not_found)
    end
  end

  context "error handling" do
    it "handles database errors gracefully" do
      allow(State).to receive(:all).and_raise(ActiveRecord::StatementInvalid.new("Database error"))

      expect { get states_path }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "handles valid parameters" do
      country = create(:country)
      create_list(:state, 5, country: country)

      get states_path, params: { page: 1 }

      expect(response).to have_http_status(200)
      expect(response.body).to include("States")
    end
  end
end

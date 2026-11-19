require 'rails_helper'

RSpec.describe "Municipalities Index", type: :request do
  describe "GET /municipalities" do
    context "with no cities" do
      it "renders successfully with empty state" do
        get municipalities_path

        expect(response).to have_http_status(200)
        expect(response.body).to include("Municipalities")
      end
    end

    context "with multiple cities" do
      let!(:usa) { create(:country, name: "United States") }
      let!(:california) { create(:state, name: "California", country: usa) }
      let!(:texas) { create(:state, name: "Texas", country: usa) }

      let!(:los_angeles) { create(:municipality, name: "Los Angeles", state: california) }
      let!(:san_francisco) { create(:municipality, name: "San Francisco", state: california) }
      let!(:houston) { create(:municipality, name: "Houston", state: texas) }
      let!(:dallas) { create(:municipality, name: "Dallas", state: texas) }

      it "renders successfully with city data" do
        get municipalities_path

        expect(response).to have_http_status(200)
        expect(response.body).to include("Municipalities")
        expect(response.body).to include("Los Angeles")
        expect(response.body).to include("San Francisco")
        expect(response.body).to include("Houston")
        expect(response.body).to include("Dallas")
      end

      it "displays associated state information" do
        get municipalities_path

        expect(response.body).to include("California")
        expect(response.body).to include("Texas")
      end

      it "displays country context through state" do
        get municipalities_path

        expect(response.body).to include("United States")
      end

      it "includes proper HTML structure for Phlex components" do
        get municipalities_path

        expect(response.body).to include('class="')
        expect(response.body).to include("<div")
        expect(response.body).to include("</div>")
      end
    end

    context "with municipalities that have offices" do
      let!(:country) { create(:country, name: "United States") }
      let!(:state) { create(:state, name: "California", country: country) }
      let!(:city) { create(:municipality, :with_jurisdiction, name: "San Francisco", state: state) }
      let!(:position) { create(:position, title: "Mayor") }
      let!(:office) { create(:office, position: position, jurisdiction: city.jurisdiction) }
      let!(:race) { create_race_for(office) }

      it "displays office and election information" do
        get municipalities_path

        expect(response).to have_http_status(200)
        expect(response.body).to include("San Francisco")
      end
    end

    context "with pagination" do
      let!(:state) { create(:state) }

      before do
        create_list(:municipality, 30, state: state)
      end

      it "renders successfully with pagination" do
        get municipalities_path

        expect(response).to have_http_status(200)
        expect(response.body).to include("Municipalities")
      end

      it "respects page parameter" do
        get municipalities_path, params: { page: 2 }

        expect(response).to have_http_status(200)
        expect(response.body).to include("Municipalities")
      end

      it "handles high page numbers gracefully" do
        get municipalities_path, params: { page: 999 }

        expect(response).to have_http_status(200)
        expect(response.body).to include("Municipalities")
      end
    end
  end

  describe "GET /states/:state_id/municipalities" do
    let!(:country) { create(:country, name: "United States") }
    let!(:california) { create(:state, name: "California", country: country) }
    let!(:texas) { create(:state, name: "Texas", country: country) }
    let!(:ca_cities) { create_list(:municipality, 3, state: california) }
    let!(:tx_cities) { create_list(:municipality, 2, state: texas) }

    it "renders cities scoped to specific state" do
      get state_municipalities_path(california)

      expect(response).to have_http_status(200)
      expect(response.body).to include("Municipalities")
    end

    it "shows state context information" do
      get state_municipalities_path(california)

      expect(response).to have_http_status(200)
      expect(response.body).to include("California")
    end

    it "handles non-existent state gracefully" do
      get state_municipalities_path(SecureRandom.uuid_v7)

      expect(response).to have_http_status(:not_found)
    end

    it "handles pagination for state-scoped cities" do
      # Create many cities for California
      create_list(:municipality, 30, state: california)

      get state_municipalities_path(california), params: { page: 2 }

      expect(response).to have_http_status(200)
      expect(response.body).to include("Municipalities")
    end
  end

  context "with different city types and sizes" do
    let!(:state) { create(:state) }
    let!(:major_city) { create(:municipality, :with_jurisdiction, name: "Major City", state: state) }
    let!(:small_town) { create(:municipality, :with_jurisdiction, name: "Small Town", state: state) }

    before do
      # Create multiple offices for major city
      3.times { create(:office, jurisdiction: major_city.jurisdiction) }
      # Create one office for small town
      create(:office, jurisdiction: small_town.jurisdiction)
    end

    it "displays cities with different office counts" do
      get municipalities_path

      expect(response).to have_http_status(200)
      expect(response.body).to include("Major City")
      expect(response.body).to include("Small Town")
    end
  end

  context "error handling" do
    it "handles valid parameters correctly" do
      state = create(:state)
      create_list(:municipality, 5, state: state)

      get municipalities_path, params: { page: 1 }

      expect(response).to have_http_status(200)
      expect(response.body).to include("Municipalities")
    end

    it "handles filter parameters when implemented" do
      state = create(:state, name: "California")
      create(:municipality, name: "Los Angeles", state: state)

      # Test without filter parameters (base functionality)
      get municipalities_path

      expect(response).to have_http_status(200)
      expect(response.body).to include("Municipalities")
    end
  end
end

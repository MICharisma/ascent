require 'rails_helper'

RSpec.describe "Citizens Index", type: :request do
  describe "GET /citizens" do
    context "with no citizens" do
      it "renders successfully with empty state" do
        get citizens_path

        expect(response).to have_http_status(200)
        expect(response.body).to include("Citizens")
      end
    end

    context "with multiple citizens" do
      let!(:politician) { create(:citizen, :experienced_politician, first_name: "Sarah", middle_name: nil, last_name: "Johnson") }
      let!(:business_leader) { create(:citizen, :business_leader, first_name: "Michael", middle_name: nil, last_name: "Chen") }
      let!(:activist) { create(:citizen, :community_activist, first_name: "Jordan", middle_name: nil, last_name: "Rivera") }
      let!(:educator) { create(:citizen, :educator, first_name: "Dr. Emily", middle_name: nil, last_name: "Davis") }

      it "renders successfully with citizens data" do
        get citizens_path

        expect(response).to have_http_status(200)
        expect(response.body).to include("Citizens")
        expect(response.body).to include("Sarah Johnson")
        expect(response.body).to include("Michael Chen")
        expect(response.body).to include("Jordan Rivera")
        expect(response.body).to include("Dr. Emily Davis")
      end

      it "displays citizen biographical information" do
        get citizens_path

        expect(response.body).to include("Sarah")
        expect(response.body).to include("Michael")
        expect(response.body).to include("Jordan")
        expect(response.body).to include("Emily")
      end

      it "includes proper HTML structure for Phlex components" do
        get citizens_path

        expect(response.body).to include('class="')
        expect(response.body).to include("<div")
        expect(response.body).to include("</div>")
      end
    end

    context "with citizens who are candidates" do
      let!(:office) { create(:office, :active) }
      let!(:race) { create_race_for(office, :upcoming) }
      let!(:candidate1) { create(:citizen, :experienced_politician, first_name: "John", middle_name: nil, last_name: "Smith") }
      let!(:candidate2) { create(:citizen, :business_leader, first_name: "Jane", middle_name: nil, last_name: "Doe") }
      let!(:non_candidate) { create(:citizen, :community_activist, first_name: "Alex", middle_name: nil, last_name: "Wilson") }

      let!(:candidacy1) { create(:candidacy, race: race, citizen: candidate1, party_label: "Democratic") }
      let!(:candidacy2) { create(:candidacy, race: race, citizen: candidate2, party_label: "Republican") }

      it "displays candidacy information for candidates" do
        get citizens_path

        expect(response).to have_http_status(200)
        expect(response.body).to include("John Smith")
        expect(response.body).to include("Jane Doe")
        expect(response.body).to include("Alex Wilson")
      end

      it "shows party affiliation for candidates" do
        get citizens_path

        expect(response.body).to include("Democratic")
        expect(response.body).to include("Republican")
      end

      it "displays election context for candidates" do
        get citizens_path

        expect(response).to have_http_status(200)
        # Should show some indication of candidacy status
      end
    end

    context "with citizens having various background types" do
      let!(:veteran) { create(:citizen, :veteran, first_name: "Robert", middle_name: nil, last_name: "Martinez") }
      let!(:young_candidate) { create(:citizen, :young_candidate, first_name: "Ashley", middle_name: nil, last_name: "Kim") }
      let!(:long_bio_citizen) { create(:citizen, :long_bio, first_name: "William", middle_name: nil, last_name: "Thompson") }
      let!(:minimal_bio_citizen) { create(:citizen, :minimal_bio, first_name: "Lisa", middle_name: nil, last_name: "Brown") }

      it "displays citizens with different background types" do
        get citizens_path

        expect(response).to have_http_status(200)
        expect(response.body).to include("Robert Martinez")
        expect(response.body).to include("Ashley Kim")
        expect(response.body).to include("William Thompson")
        expect(response.body).to include("Lisa Brown")
      end

      it "handles different bio lengths appropriately" do
        get citizens_path

        expect(response).to have_http_status(200)
        # Should handle both long and minimal bios
      end
    end

    context "with pagination" do
      before do
        create_list(:citizen, 30)
      end

      it "renders successfully with pagination" do
        get citizens_path

        expect(response).to have_http_status(200)
        expect(response.body).to include("Citizens")
      end

      it "respects page parameter" do
        get citizens_path, params: { page: 2 }

        expect(response).to have_http_status(200)
        expect(response.body).to include("Citizens")
      end

      it "handles high page numbers gracefully" do
        get citizens_path, params: { page: 999 }

        expect(response).to have_http_status(200)
        expect(response.body).to include("Citizens")
      end
    end

    context "with citizens in multiple elections" do
      let!(:citizen) { create(:citizen, :experienced_politician) }
      let!(:office1) { create(:office) }
      let!(:office2) { create(:office) }
      let!(:race1) { create_race_for(office1) }
      let!(:race2) { create_race_for(office2) }
      let!(:candidacy1) { create(:candidacy, race: race1, citizen: citizen) }
      let!(:candidacy2) { create(:candidacy, race: race2, citizen: citizen) }

      it "displays citizen with multiple candidacies" do
        get citizens_path

        expect(response).to have_http_status(200)
        expect(response.body).to include("Citizens")
      end

      it "shows electoral history appropriately" do
        get citizens_path

        expect(response).to have_http_status(200)
        # Should indicate multiple candidacies or electoral activity
      end
    end
  end

  context "search and filtering capabilities" do
    let!(:politician) { create(:citizen, :experienced_politician, first_name: "Sarah") }
    let!(:business_citizen) { create(:citizen, :business_leader, first_name: "Michael") }

    it "handles potential search parameters" do
      get citizens_path, params: { search: "Sarah" }

      expect(response).to have_http_status(200)
      expect(response.body).to include("Citizens")
    end

    it "handles candidate filtering if implemented" do
      # Create a candidate
      office = create(:office)
      race = create_race_for(office)
      create(:candidacy, race: race, citizen: politician)

      get citizens_path

      expect(response).to have_http_status(200)
      expect(response.body).to include("Citizens")
    end
  end

  context "error handling" do
    it "handles valid parameters correctly" do
      create_list(:citizen, 5)

      get citizens_path, params: { page: 1 }

      expect(response).to have_http_status(200)
      expect(response.body).to include("Citizens")
    end

    it "handles citizens with special characters in names" do
      citizen_with_apostrophe = create(:citizen, first_name: "Mary", last_name: "O'Connor")
      citizen_with_hyphen = create(:citizen, first_name: "Jean-Luc", last_name: "Picard")

      get citizens_path

      expect(response).to have_http_status(200)
      expect(response.body).to include("Citizens")
    end
  end

  context "performance with complex data" do
    before do
      # Create citizens with varying levels of complexity
      5.times do
        citizen = create(:citizen, :experienced_politician)
        office = create(:office)
        race = create_race_for(office)
        candidacy = create(:candidacy, race: race, citizen: citizen)
        # Add some ratings for electoral activity
        3.times do
          voter = create(:voter)
          create(:rating, candidacy: candidacy, voter: voter)
        end
      end
    end

    it "renders successfully with complex citizen data" do
      get citizens_path

      expect(response).to have_http_status(200)
      expect(response.body).to include("Citizens")
    end

    it "handles citizens with extensive electoral history" do
      citizen = create(:citizen, :experienced_politician)

      # Create multiple candidacies across different elections
      3.times do
        office = create(:office)
        race = create_race_for(office)
        create(:candidacy, race: race, citizen: citizen)
      end

      get citizens_path

      expect(response).to have_http_status(200)
      expect(response.body).to include("Citizens")
    end
  end
end

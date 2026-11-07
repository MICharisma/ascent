require 'rails_helper'

RSpec.describe "Candidate Management", type: :system do
  before do
    driven_by(:rack_test)
  end

  let!(:country) { create(:country, name: "United States") }
  let!(:california) { create(:state, :with_jurisdiction, name: "California", country: country) }
  let!(:year) { create(:year, year: 2024) }
  let!(:governor) { create(:position, :governor, description: "Chief executive of the state") }
  let!(:office) { create(:office, position: governor, jurisdiction: california.jurisdiction) }
  let!(:race) { create_race_for(office, :upcoming, year: year) }

  let!(:citizen) { create(:citizen, first_name: "Sarah", middle_name: nil, last_name: "Martinez", bio: "Experienced public servant") }

  describe "citizen registration and candidacy announcement" do
    it "shows citizen profiles in the system" do
      visit citizens_path

      expect(page).to have_content("Citizens")
      expect(page).to have_content("Sarah Martinez")
    end

    it "displays citizen biographical information" do
      visit citizen_path(citizen)

      expect(page).to have_content("Sarah Martinez")
      expect(page).to have_content("Experienced public servant")
    end

    context "when citizen becomes a candidate" do
      let!(:candidacy) { create(:candidacy, status: "announced", citizen: citizen, race: race, announcement_date: 1.month.ago) }

      it "shows candidacy in the candidacies listing" do
        visit candidacies_path

        expect(page).to have_content("Candidacies")
        expect(page).to have_content("Sarah Martinez")
        expect(page).to have_content("Governor")
      end

      it "displays candidacy details" do
        visit candidacy_path(candidacy)

        expect(page).to have_content("Sarah Martinez")
        expect(page).to have_content("Governor of California")
        expect(page).to have_content("announced")
      end

      it "shows candidacy status transitions" do
        # Start as announced
        expect(candidacy.status).to eq("announced")

        # Can transition to active
        candidacy.update!(status: "active")
        visit candidacy_path(candidacy)
        expect(page).to have_content("active")

        # Can transition to withdrawn
        candidacy.update!(status: "withdrawn")
        visit candidacy_path(candidacy)
        expect(page).to have_content("withdrawn")
      end
    end
  end

  describe "multiple candidates in a race" do
    let!(:candidate1) { create(:citizen, first_name: "Alice", middle_name: nil, last_name: "Johnson") }
    let!(:candidate2) { create(:citizen, first_name: "Bob", middle_name: nil, last_name: "Wilson") }
    let!(:candidate3) { create(:citizen, first_name: "Carol", middle_name: nil, last_name: "Davis") }

    let!(:candidacy1) { create(:candidacy, :active, citizen: candidate1, race: race) }
    let!(:candidacy2) { create(:candidacy, :active, citizen: candidate2, race: race) }
    let!(:candidacy3) { create(:candidacy, :withdrawn, citizen: candidate3, race: race) }

    it "shows all candidates for a race" do
      visit race_path(race)

      # Candidates render inside a collapsed expandable section.
      expect(page).to have_text(:all, "Alice Johnson")
      expect(page).to have_text(:all, "Bob Wilson")
      expect(page).to have_text(:all, "Carol Davis")
    end

    it "differentiates candidate statuses" do
      visit candidacies_path

      # Should show different statuses
      expect(page).to have_content("active")
      expect(page).to have_content("withdrawn")
    end

    it "filters candidates by status" do
      active_candidacies = race.candidacies.active
      expect(active_candidacies).to include(candidacy1, candidacy2)
      expect(active_candidacies).not_to include(candidacy3)

      withdrawn_candidacies = race.candidacies.withdrawn
      expect(withdrawn_candidacies).to include(candidacy3)
      expect(withdrawn_candidacies).not_to include(candidacy1, candidacy2)
    end
  end

  describe "candidate performance tracking" do
    let!(:candidacy) { create(:candidacy, :active, citizen: citizen, race: race) }
    let!(:voter1) { create(:voter) }
    let!(:voter2) { create(:voter) }
    let!(:voter3) { create(:voter) }

    context "with voter ratings" do
      before do
        create(:rating, voter: voter1, candidacy: candidacy, rating: 450)
        create(:rating, voter: voter2, candidacy: candidacy, rating: 300)
        create(:rating, voter: voter3, candidacy: candidacy, rating: 200)
      end

      it "calculates average ratings correctly" do
        expect(candidacy.average_rating).to eq(316.7) # (450 + 300 + 200) / 3 = 316.67, rounded to 316.7
      end

      it "shows approval counts based on baseline" do
        baseline_250 = 250
        expect(candidacy.approval_count(baseline_250)).to eq(2) # 450 and 300 are > 250
        expect(candidacy.approval_percentage(baseline_250)).to eq(66.7) # 2/3 = 66.67%, rounded to 66.7%

        baseline_350 = 350
        expect(candidacy.approval_count(baseline_350)).to eq(1) # Only 450 is > 350
        expect(candidacy.approval_percentage(baseline_350)).to eq(33.3) # 1/3 = 33.33%, rounded to 33.3%
      end

      it "displays rating information in the system" do
        sign_in create(:voter, admin: true)
        visit ratings_path

        expect(page).to have_content("450")
        expect(page).to have_content("300")
        expect(page).to have_content("200")
      end
    end
  end

  describe "office and position context" do
    let!(:candidacy) { create(:candidacy, citizen: citizen, race: race) }

    it "shows office and position information" do
      visit offices_path

      expect(page).to have_content("California")
      expect(page).to have_content("Governor")
    end

    it "shows position descriptions" do
      visit positions_path

      expect(page).to have_content("Governor")
      expect(page).to have_content("Chief executive")
    end

    it "links candidates to their office context" do
      expect(candidacy.name).to eq("Sarah Martinez for Governor")
    end
  end
end

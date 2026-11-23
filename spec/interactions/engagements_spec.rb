# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Saved page engagements" do
  let(:voter) { create(:voter) }
  let(:citizen) { create(:citizen, first_name: "Marisol", last_name: "Vega") }

  def engage(*kinds)
    kinds.each { |kind| create(:engagement, actor: voter, engageable: citizen, kind: kind) }
    sign_in voter
    visit "/saved"
  end

  context "with a citizen bookmarked and hidden" do
    before { engage(:bookmark, :hide) }

    it "replaces the unhidden row with an Undo patch and updates the citizen's other rows" do
      within(".saved-section.saved-hide") do
        click_button "Unhide"
        expect(page).to have_text("Removed #{citizen.name} from Hidden.")
        expect(page).to have_button("Undo")
        expect(page).to have_no_css(".action-bar")
      end
      within(".saved-section.saved-bookmark") do
        expect(page).to have_button("Hide")
        expect(page).to have_no_button("Unhide")
      end
    end

    it "restores the row and the other rows' state with Undo" do
      within(".saved-section.saved-hide") { click_button "Unhide" }
      within(".saved-section.saved-hide") do
        click_button "Undo"
        expect(page).to have_css(".saved-item.is-restoring")
        expect(page).to have_button("Unhide")
      end
      within(".saved-section.saved-bookmark") { expect(page).to have_button("Unhide") }
    end
  end

  context "with a citizen bookmarked, favorited and hidden" do
    before { engage(:bookmark, :favorite, :hide) }

    it "replaces the unfavorited row with Undo and updates both remaining rows" do
      within(".saved-section.saved-favorite") do
        click_button "Favorited"
        expect(page).to have_text("Removed #{citizen.name} from Favorites.")
        expect(page).to have_button("Undo")
      end
      %w[bookmark hide].each do |section|
        within(".saved-section.saved-#{section}") do
          expect(page).to have_button("Favorite")
          expect(page).to have_no_button("Favorited")
        end
      end
    end

    it "keeps updating the remaining rows after a second removal" do
      within(".saved-section.saved-favorite") { click_button "Favorited" }
      within(".saved-section.saved-hide") do
        click_button "Unhide"
        expect(page).to have_text("Removed #{citizen.name} from Hidden.")
      end
      within(".saved-section.saved-bookmark") do
        expect(page).to have_button("Hide")
        expect(page).to have_no_button("Unhide")
      end
    end
  end
end

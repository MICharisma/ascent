# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Saved page engagements" do
  it "replaces the removed section's row with an Undo patch and updates other rows when unhiding" do
    voter = create(:voter)
    citizen = create(:citizen, first_name: "Marisol", last_name: "Vega")
    create(:engagement, actor: voter, engageable: citizen, kind: :bookmark)
    create(:engagement, actor: voter, engageable: citizen, kind: :hide)

    sign_in voter
    visit "/saved"

    within(".saved-section.saved-hide") do
      click_button "Unhide"
      expect(page).to have_css(".saved-undo-patch")
      expect(page).to have_text("Removed #{citizen.name} from Hidden.")
      expect(page).to have_button("Undo")
      expect(page).not_to have_css(".action-bar")
    end

    within(".saved-section.saved-bookmark") do
      expect(page).to have_button("Hide")
      expect(page).not_to have_button("Unhide")
    end

    within(".saved-section.saved-hide") do
      click_button "Undo"
      expect(page).to have_css(".saved-item.is-restoring")
      expect(page).to have_button("Unhide")
    end

    within(".saved-section.saved-bookmark") do
      expect(page).to have_button("Unhide")
    end
  end

  it "updates remaining rows and replaces the deselected section with Undo when a citizen has three engagements" do
    voter = create(:voter)
    citizen = create(:citizen, first_name: "Marisol", last_name: "Vega")
    create(:engagement, actor: voter, engageable: citizen, kind: :bookmark)
    create(:engagement, actor: voter, engageable: citizen, kind: :favorite)
    create(:engagement, actor: voter, engageable: citizen, kind: :hide)

    sign_in voter
    visit "/saved"

    within(".saved-section.saved-favorite") do
      click_button "Favorited"
      expect(page).to have_text("Removed #{citizen.name} from Favorites.")
      expect(page).to have_button("Undo")
    end

    %w[bookmark hide].each do |section|
      within(".saved-section.saved-#{section}") do
        expect(page).to have_button("Favorite")
        expect(page).not_to have_button("Favorited")
      end
    end

    within(".saved-section.saved-hide") do
      click_button "Unhide"
      expect(page).to have_text("Removed #{citizen.name} from Hidden.")
      expect(page).to have_button("Undo")
    end

    within(".saved-section.saved-bookmark") do
      expect(page).to have_button("Hide")
      expect(page).not_to have_button("Unhide")
    end
  end
end

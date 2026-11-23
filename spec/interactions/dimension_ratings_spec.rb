require "rails_helper"

# The quality rows on a citizen's page. Dragging is in
# spec/system/dimension_rating_gestures_spec.rb.
RSpec.describe "Dimension rating controls" do
  let(:voter) { create(:voter, first_name: "Teodora", last_name: "Lindqvist") }
  let!(:citizen) { create(:citizen, first_name: "Marisol", middle_name: nil, last_name: "Okafor", bio: nil) }

  before { sign_in voter }

  def row_for(quality) = find("##{ActionView::RecordIdentifier.dom_id(citizen, "#{quality}_rating")}")
  def focused_id = evaluate_script("document.activeElement.id")

  def expect_saved(row, value)
    expect(row).to have_css(".dimension-rating-value", text: value)
    expect(row).to have_css(".status-indicator", text: "Saved")
    expect(row).to have_css("input:not([disabled])")
  end

  it "opens an unrated quality from the picker with its slider focused" do
    visit citizen_path(citizen)
    click_button "Trustworthiness"
    row = row_for(:trustworthiness)
    expect(row).to have_css(".dimension-rating-value", text: "Not rated")
    expect(focused_id).to eq(row.find("input")[:id])
  end

  it "rates an unrated quality neutral on request" do
    visit citizen_path(citizen)
    click_button "Trustworthiness"
    within(row_for(:trustworthiness)) { click_button "Rate neutral" }
    expect_saved row_for(:trustworthiness), "0"
    expect(voter.dimension_ratings.sole).to have_attributes(dimension_key: "ascent.citizen.trustworthiness", value: 0)
  end

  context "with a suggestion provider" do
    around do |example|
      previous = Rails.configuration.x.shared_ratings.suggestion_provider
      Rails.configuration.x.shared_ratings.suggestion_provider = ->(**) { %w[ascent.citizen.trustworthiness] }
      example.run
    ensure
      Rails.configuration.x.shared_ratings.suggestion_provider = previous
    end

    before { create(:dimension_rating, :capable_candidate, voter: voter, rated: citizen, value: 300) }

    it "suggests qualities on request and opens the one chosen" do
      visit citizen_path(citizen)
      within(".dimension-picker") do
        expect(page).to have_css(".dimension-suggestions button", count: 2)
        click_button "Suggest for me"
        expect(page).to have_css(".dimension-suggestions-status", text: "AI suggestions")
        expect(all(".dimension-suggestions button").map(&:text)).to eq(%w[Trustworthiness Familiarity])
        click_button "Trustworthiness"
      end
      expect(row_for(:trustworthiness)).to have_css(".dimension-rating-value", text: "Not rated")
      expect(focused_id).to eq(row_for(:trustworthiness).find("input")[:id])
    end

    it "opens any quality from the full picker without rating it" do
      visit citizen_path(citizen)
      select "Competence", from: "Choose a quality"
      expect(focused_id).to eq(row_for(:competence).find("input")[:id])
      expect(find_field("Choose a quality").value).to eq("")
      expect(DimensionRating.count).to eq(1)
    end
  end

  context "with a saved rating" do
    before { create(:dimension_rating, :capable_candidate, voter: voter, rated: citizen, value: 300) }

    it "adjusts by keyboard in fine steps" do
      visit citizen_path(citizen)
      click_button "Fine"
      row_for(:competence).find("input").send_keys(:arrow_right)
      expect_saved row_for(:competence), "+301"
      expect(voter.dimension_ratings.sole.value).to eq(301)
    end

    it "clears back to unrated and records each revision" do
      visit citizen_path(citizen)
      click_button "Fine"
      row_for(:competence).find("input").send_keys(:arrow_right)
      within(row_for(:competence)) { click_button "Clear" }
      expect(row_for(:competence)).to have_css(".dimension-rating-value", text: "Not rated")
      expect(row_for(:competence)).to have_button("Rate neutral")
      expect(voter.dimension_ratings).to be_empty
      expect(voter.dimension_rating_revisions.order(:id).pluck(:event)).to eq(%w[rate change clear])
    end
  end
end

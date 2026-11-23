require "rails_helper"

# Dragging a quality row needs a real pointer: a held drag switches into fine
# steps by moving down, saves once on release, and Escape puts the row back.
# Keys, the picker, Rate neutral and Clear are in spec/interactions.
RSpec.describe "Dimension rating gestures", type: :system do
  let(:voter) { create(:voter, first_name: "Teodora", last_name: "Lindqvist") }
  let!(:citizen) { create(:citizen, first_name: "Marisol", middle_name: nil, last_name: "Okafor", bio: nil) }

  before do
    sign_in voter
  end

  def row_for(quality)
    find("##{ActionView::RecordIdentifier.dom_id(citizen, "#{quality}_rating")}")
  end

  def browser
    page.driver.browser
  end

  def coarse_distance(row)
    slider = row.find("input")
    # Ascent scrolls smoothly; an instant scroll keeps the page still before the pointer goes down.
    page.execute_script("arguments[0].scrollIntoView({block: 'center', behavior: 'instant'})", slider)
    ((slider.native.rect.width - 24) / 60).round
  end

  def expect_saved(row, value)
    expect(row).to have_css(".dimension-rating-value", text: value)
    expect(row).to have_css(".status-indicator", text: "Saved")
    expect(row).to have_css("input:not([disabled])")
  end

  it "switches a held drag into fine steps and saves only on release" do
    create(:dimension_rating, :well_known_candidate, voter: voter, rated: citizen, value: 43)
    visit citizen_path(citizen)
    row = row_for(:familiarity)
    distance = coarse_distance(row)

    browser.action.move_to(row.find(".dimension-rating-handle").native).click_and_hold.perform
    browser.action.move_by(distance, 0).perform
    expect(row).to have_css(".dimension-rating-value", text: "+53")
    browser.action.move_by(0, 40).perform
    expect(row).to have_css(".drag-precision", text: "Fine")
    expect(row).to have_css(".dimension-rating-value", text: "+53")
    browser.action.move_by(distance, 0).perform
    expect(row).to have_css(".dimension-rating-value", text: "+54")
    browser.action.move_by(0, -40).perform
    expect(row).to have_css(".dimension-rating-value", text: "+54")
    expect(voter.dimension_rating_revisions.count).to eq(1)

    browser.action.release.perform
    expect_saved row, "+54"
    expect(voter.dimension_ratings.sole.value).to eq(54)
    expect(voter.dimension_rating_revisions.order(:id).pluck(:event, :value)).to eq([ [ "rate", 43 ], [ "change", 54 ] ])
  end

  it "cancels a drag on an unrated quality with Escape" do
    visit citizen_path(citizen)
    click_button "Trustworthiness"
    row = row_for(:trustworthiness)

    coarse_distance(row)
    browser.action.move_to(row.find(".dimension-rating-handle").native).click_and_hold.move_by(80, 0).perform
    expect(row).to have_content("Not saved yet")
    browser.action.send_keys(:escape).release.perform
    expect(row).to have_css(".dimension-rating-value", text: "Not rated")
    expect(row.find("input")["aria-valuetext"]).to eq("Not rated")
    expect(DimensionRating.count).to eq(0)
  end
end

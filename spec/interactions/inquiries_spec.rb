require "rails_helper"

RSpec.describe "Inquiries" do
  it "fills a subject from a button and submits an editable inquiry" do
    visit new_inquiry_path
    click_button "I want to invest"
    expect(page).to have_field("Subject", with: "I want to invest")
    fill_in "Email", with: "marisol.vega@example.com"
    fill_in "Subject", with: "Supporting a local election experiment"
    fill_in "Message", with: "Our civic group would like to discuss an approval-voting demonstration."
    click_button "Send inquiry"
    expect(page).to have_content("Your inquiry has been sent.")
    expect(page).to have_current_path(new_inquiry_path)
  end
end

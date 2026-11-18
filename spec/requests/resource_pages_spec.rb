require 'rails_helper'

# Reference data without a page of its own, such as positions and areas of concern, renders its index and
# show pages through the shared ResourceIndex and ResourceShow shells.
RSpec.describe "Resource index and show pages", type: :request do
  let(:admin) { create(:admin_voter) }

  describe "an index page" do
    let!(:council_member) { create(:position, title: "City Council Member") }
    let!(:mayor) { create(:position, :executive) }

    it "lists each record as a row under the model's name" do
      get positions_path

      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(page.at_css("h1").text).to eq("Positions")
      expect(page.css(".list-row-title").map(&:text)).to eq([ "City Council Member", "Mayor" ])
      expect(page.at_css("#list_item_position_#{mayor.id} .list-row-meta").text).to start_with("Executive")
    end

    it "offers the new link only to admins" do
      get positions_path
      expect(response.body).not_to include("New position")

      sign_in admin
      get positions_path
      expect(Nokogiri::HTML(response.body).at_css(%(.page-header a[href="#{new_position_path}"])).text).to eq("New position")
    end

    it "pages the records once there are more than a page of them" do
      create_list(:position, Pagy::OPTIONS[:limit])

      get positions_path

      expect(response.body).to include(%(<nav class="pagination" aria-label="Pagination">), "Showing 1–25 of")
      expect(response.body.scan(/id="list_item_position_\d+"/).size).to eq(Pagy::OPTIONS[:limit])
    end
  end

  it "names the empty state after the model" do
    get area_of_concerns_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No area of concerns yet", "None has been added to Ascent.")
  end

  describe "a show page" do
    it "titles the record by name under its section, with its partial's sections and admin actions" do
      area = create(:area_of_concern, :housing)

      get area_of_concern_path(area)

      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(page.at_css("h1").text).to eq(area.name)
      expect(page.css(".breadcrumb a").map(&:text)).to eq([ "Area of concerns" ])
      expect(page.at_css(".place-facts-list").text).to include(area.policy_domain)
      expect(page.at_css(".admin-card")).to be_nil

      sign_in admin
      get area_of_concern_path(area)

      expect(Nokogiri::HTML(response.body).at_css(".admin-card")).to be_present
    end
  end
end

# Every list with a page design of its own offers admins the same New link in its header.
RSpec.describe "New links on designed lists", type: :request do
  {
    races: :new_race_path, citizens: :new_citizen_path, offices: :new_office_path, candidacies: :new_candidacy_path,
    states: :new_state_path, counties: :new_county_path, districts: :new_district_path, municipalities: :new_municipality_path,
    topics: :new_topic_path, issues: :new_issue_path, approaches: :new_approach_path, stances: :new_stance_path,
    governing_bodies: :new_governing_body_path, policies: :new_policy_path, official_codes: :new_official_code_path
  }.each do |list, new_path|
    it "shows the #{list} list's New link to admins only" do
      get send("#{list}_path")
      expect(response.body).not_to include(%(href="#{send(new_path)}"))

      sign_in create(:admin_voter)
      get send("#{list}_path")
      expect(Nokogiri::HTML(response.body).at_css(%(.page-header a[href="#{send(new_path)}"]))).to be_present
    end
  end
end

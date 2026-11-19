require 'rails_helper'

# A record's page previews its first five children and links to the rest.
# That link goes to the children's index, filtered to this parent.
RSpec.describe "Links to a record's children", type: :request do
  describe "a governance type with more governing bodies than the preview shows" do
    let!(:council) { create(:governance_type, :council) }
    let!(:council_bodies) do
      %w[Ann\ Arbor Detroit Flint Lansing Kalamazoo Grand\ Rapids].map do |city|
        create(:governing_body, name: "#{city} City Council", governance_type: council)
      end
    end
    let!(:court) { create(:governing_body, name: "Michigan Supreme Court", governance_type: create(:governance_type, :court)) }

    it "counts each governance type's bodies, and previews them with a link to all of them" do
      get governance_types_path

      expect(response).to have_http_status(:ok)
      row = Nokogiri::HTML(response.body).at_css("#list_item_governance_type_#{council.id}")
      expect(row.at_css(".list-row-meta").text).to eq("6 governing bodies")

      get governance_type_path(council)

      page = Nokogiri::HTML(response.body)
      expect(page.css(".related-list .list-row").size).to eq(5)
      expect(page.at_css(%(a[href="#{governance_type_governing_bodies_path(council)}"])).text).to eq("See all 6 governing bodies")
    end

    it "lists only that governance type's bodies at the link" do
      get governance_type_governing_bodies_path(council)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Grand Rapids City Council", "Ann Arbor City Council")
      expect(response.body).not_to include("Michigan Supreme Court")
    end

    it "names the governance type in the heading and leads back to every governing body" do
      get governance_type_governing_bodies_path(council)

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("h1").text).to eq("Governing bodies for #{council.name}")
      expect(page.at_css(".breadcrumb a")["href"]).to eq(governing_bodies_path)
    end

    it "answers not found for a governance type that does not exist" do
      get governance_type_governing_bodies_path(governance_type_id: SecureRandom.uuid_v7)

      expect(response).to have_http_status(:not_found)
    end
  end

  it "filters the other children indexes by their parent" do
    housing_issue = create(:affordable_housing_issue)
    school_issue = create(:school_funding_issue)

    get topic_issues_path(housing_issue.topic)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Affordable Housing Shortage")
    expect(response.body).not_to include("Inadequate School Funding")

    [
      issue_approaches_path(school_issue),
      governing_body_policies_path(create(:governing_body)),
      policy_official_codes_path(create(:policy))
    ].each do |path|
      get path
      expect(response).to have_http_status(:ok)
    end
  end
end

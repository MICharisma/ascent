require "rails_helper"

# The policy pages read as one path, from a topic to an issue to the approaches to it, and on to the
# candidates who take an approach and the laws that put it in place.
RSpec.describe "Policy pages", type: :request do
  let(:housing) { create(:topic, title: "Housing", description: nil) }
  let(:rents) { create(:issue, title: "Rents", topic: housing, description: "Rents rose faster than wages.") }
  let(:rent_cap) { create(:approach, title: "Cap annual rent increases", issue: rents, description: "Limit yearly increases to inflation.") }
  let!(:vouchers) { create(:approach, title: "Expand housing vouchers", issue: rents) }
  let(:okafor) { create(:candidacy, status: "active", citizen: create(:citizen, first_name: "Dana", middle_name: nil, last_name: "Okafor")) }
  let!(:stance) { create(:stance, candidacy: okafor, approach: rent_cap, priority_level: "high", explanation: "Families cannot plan when rents jump.", evidence_links: nil) }
  let(:council) { create(:governing_body, name: "Port Merritt City Council") }
  let!(:ordinance) { create(:policy, title: "Rent Stabilization Ordinance", approach: rent_cap, governing_body: council, status: "enacted") }

  it "shows a topic's issues with the approaches to each, and where the page sits on the path" do
    get topic_path(housing)

    page = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(page.at_css(".issue-card-title").text).to eq("Rents")
    expect(page.css(".issue-card-approaches a").map(&:text)).to eq([ "Cap annual rent increases", "Expand housing vouchers" ])
    expect(page.at_css(".policy-path-step.is-current .policy-path-name").text).to eq("Housing")
    expect(page.css(".related-list .list-row-title").map(&:text)).to include("Dana Okafor", "Rent Stabilization Ordinance")
  end

  it "counts on an issue's page the candidates and laws behind each approach" do
    get issue_path(rents)

    page = Nokogiri::HTML(response.body)
    expect(page.css(".breadcrumb a").map(&:text)).to eq([ "Housing" ])
    rows = page.css("#issue-approaches .list-row").to_h { [ it.at_css(".list-row-title").text, it.at_css(".list-row-meta").text ] }
    expect(rows).to eq("Cap annual rent increases" => "1 candidate · 1 law", "Expand housing vouchers" => "0 candidates · 0 laws")
  end

  it "sets on an approach's page the candidates who take it beside the laws that put it in place" do
    get approach_path(rent_cap)

    page = Nokogiri::HTML(response.body)
    expect(page.css(".breadcrumb a").map(&:text)).to eq([ "Housing", "Rents" ])
    expect(page.css("#approach-stances .list-row-title").map(&:text)).to eq([ "Dana Okafor" ])
    expect(page.css("#approach-policies .list-row-title").map(&:text)).to eq([ "Rent Stabilization Ordinance" ])

    get approach_path(vouchers)

    expect(response.body).to include("No candidate has taken this approach yet.", "No law on Ascent puts this approach in place yet.")
  end

  it "gives a stance's evidence with its quote, and the path back to the issue" do
    create(:stance_evidence, stance: stance, quote: "Rent should rise no faster than paychecks.", offset_seconds: 102,
      communication: create(:communication, title: "Town hall on housing", url: "https://example.com/town-hall"))

    get stance_path(stance)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css("h1").text).to eq("Dana Okafor on Cap annual rent increases")
    expect(page.css(".breadcrumb a").map(&:text)).to eq([ "Housing", "Rents", "Cap annual rent increases" ])
    expect(page.at_css(".evidence-quote").text).to eq("Rent should rise no faster than paychecks.")
    expect(page.at_css(".communication-meta").text).to include("at 1:42")
  end

  it "lists a governing body's laws and links its seats to the offices list" do
    office = create(:office, governing_body: council)

    get governing_body_path(council)

    page = Nokogiri::HTML(response.body)
    expect(page.css("#body-policies .list-row-title").map(&:text)).to eq([ "Rent Stabilization Ordinance" ])
    expect(response.body).to include(%(id="list_item_office_#{office.id}"))

    get offices_path, params: { governing_body_id: council.id }

    expect(response.body).to include(%(id="list_item_office_#{office.id}"))
  end

  it "places a law under its body, with its code and the candidates who take its approach" do
    code = create(:official_code, policy: ordinance, title: "Annual Rent Increase Limit", code_number: "Municipal Code 9.1")

    get policy_path(ordinance)

    page = Nokogiri::HTML(response.body)
    expect(page.css(".breadcrumb a").map(&:text)).to eq([ "Governing bodies", "Port Merritt City Council" ])
    expect(page.css("#policy-codes .list-row-title").map(&:text)).to eq([ "Annual Rent Increase Limit" ])
    expect(page.css(".policy-path-name").map(&:text).first(3)).to eq([ "Housing", "Rents", "Cap annual rent increases" ])

    get official_code_path(code)

    expect(Nokogiri::HTML(response.body).css(".breadcrumb a").map(&:text)).to eq([ "Governing bodies", "Port Merritt City Council", "Rent Stabilization Ordinance" ])
  end

  it "narrows the lists by search, topic, status and priority" do
    other = create(:issue, title: "School funding", topic: create(:topic, title: "Education"))
    repealed = create(:policy, title: "Vacancy Tax", governing_body: council, status: "repealed")

    get issues_path, params: { topic_id: housing.id }
    expect(response.body).to include(%(id="list_item_issue_#{rents.id}"))
    expect(response.body).not_to include(%(id="list_item_issue_#{other.id}"))

    get policies_path, params: { status: "repealed" }
    expect(response.body).to include(%(id="list_item_policy_#{repealed.id}"))
    expect(response.body).not_to include(%(id="list_item_policy_#{ordinance.id}"))

    get stances_path, params: { q: "okafor", priority_level: "high" }
    expect(response.body).to include(%(id="list_item_stance_#{stance.id}"))

    get stances_path, params: { priority_level: "low" }
    expect(response.body).not_to include(%(id="list_item_stance_#{stance.id}"))
  end
end

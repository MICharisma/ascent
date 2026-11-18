require "rails_helper"

RSpec.describe "Organizations, parties and endorsements", type: :request do
  let!(:calder) { create(:state, name: "Calder", code: "CA") }
  let!(:union) { create(:organization, :union, state: calder, abbreviation: "HWU") }
  let!(:party) { Party.create!(name: "Calder Forward Party", abbreviation: "CFP", state: calder) }
  let!(:other_party) { Party.create!(name: "Lakeshore Forward Party", state: create(:state, name: "Lakeshore", code: "LS")) }
  let(:candidacy) { create(:candidacy, citizen: create(:citizen, first_name: "Dana", middle_name: nil, last_name: "Okafor")) }

  def page
    Nokogiri::HTML(response.body)
  end

  it "links all three directories from the menu and includes parties among organizations" do
    get organizations_path

    expect(response).to have_http_status(:ok)
    expect(page.css(".list-row-title").map(&:text)).to contain_exactly(union.name, party.name, other_party.name)
    [ organizations_path, parties_path, endorsements_path ].each do |path|
      expect(page.at_css(%(.main-navigation a[href="#{path}"]))).to be_present
    end
    expect(page.at_css("form.filter-form")["data-controller"]).to eq("form-submit")
  end

  it "combines organization search, state and kind filters" do
    get organizations_path, params: { q: "hwu", state_id: calder.id, kind: "union" }

    expect(page.css(".list-row-title").map(&:text)).to eq([ union.name ])
    expect(page.at_css("select[name=kind] option[selected]")["value"]).to eq("union")

    get organizations_path, params: { kind: "party", state_id: calder.id }
    expect(page.css(".list-row-title").map(&:text)).to eq([ party.name ])
    expect(page.at_css(".list-row-title")["href"]).to eq(party_path(party))
  end

  it "keeps the party directory limited to parties and filters by state and abbreviation" do
    get parties_path, params: { state_id: calder.id, q: "cfp" }

    expect(response).to have_http_status(:ok)
    expect(page.css(".list-row-title").map(&:text)).to eq([ party.name ])
    expect(page.at_css("select[name=kind]")).to be_nil
  end

  it "shows an organization's current endorsements, channels and nominating offices" do
    current = create(:endorsement, candidacy: candidacy, endorser: union)
    withdrawn = create(:endorsement, :withdrawn, endorser: union)
    Channel.create!(owner: union, official: true, platform: "website", handle: "Harbor Workers", url: "https://example.org")
    office = candidacy.office
    nomination = create(:office, position: create(:position, title: Position::NOMINEE_TITLE), jurisdiction: office.jurisdiction,
      nominee_for: office, nominating_organization: union, nominee_count: 1)

    get organization_path(union)

    expect(response).to have_http_status(:ok)
    expect(page.at_css(%(a[href="#{endorsement_path(current)}"]))).to be_present
    expect(page.at_css(%(a[href="#{endorsement_path(withdrawn)}"]))).to be_nil
    expect(page.at_css(%(a[href="#{office_path(nomination)}"]))).to be_present
    expect(page.at_css(%(a[href="#{endorsements_path(organization_id: union.id)}"]))).to be_present
    expect(page.at_css('.profile-channel a[rel="noopener"]').text).to include("Harbor Workers")
    expect(page.at_css(".communication-meta").text).to eq("Organization")
  end

  it "opens a party profile and supports empty profiles" do
    get party_path(party)

    expect(response).to have_http_status(:ok)
    expect(page.at_css("h1").text).to eq(party.name)
    expect(response.body).to include("No current endorsements are recorded.", "No nominating offices are recorded.")
    expect(page.at_css(%(a[href="#{state_path(calder)}"]))).to be_present
  end

  it "combines endorsement name, kind and withdrawal filters, including personal endorsers" do
    current = create(:endorsement, candidacy: candidacy, endorser: union)
    citizen = create(:citizen, first_name: "Mara", middle_name: nil, last_name: "Delgado")
    withdrawn = create(:endorsement, :withdrawn, candidacy: candidacy, endorser: citizen)
    BallotLine.create!(candidacy: candidacy, party: party, label: party.name, kind: "party")

    get endorsements_path, params: { q: "Okafor", kind: "public", status: "current" }
    expect(response).to have_http_status(:ok)
    expect(page.css(".list-row").map { it["id"] }).to eq([ "list_item_endorsement_#{current.id}" ])

    get endorsements_path, params: { q: "Delgado", status: "withdrawn" }
    expect(page.css(".list-row").map { it["id"] }).to eq([ "list_item_endorsement_#{withdrawn.id}" ])

    get endorsements_path, params: { q: "HWU" }
    expect(page.css(".list-row").map { it["id"] }).to eq([ "list_item_endorsement_#{current.id}" ])
  end

  it "keeps the organization context while filtering its endorsement history and clears all filters" do
    endorsement = create(:endorsement, :withdrawn, endorser: union)
    create(:endorsement, endorser: party)

    get endorsements_path, params: { organization_id: union.id, status: "withdrawn" }

    expect(page.at_css("h1").text).to include(union.name)
    expect(page.css(".list-row").map { it["id"] }).to eq([ "list_item_endorsement_#{endorsement.id}" ])
    expect(page.at_css('input[name="organization_id"]')["value"]).to eq(union.id.to_s)
    expect(page.at_css('.filter-actions a')["href"]).to eq(endorsements_path)
  end

  it "shows endorsement details with party, candidacy and election links" do
    line = BallotLine.create!(candidacy: candidacy, party: party, label: party.name, kind: "party")
    get endorsement_path(line.endorsement)

    expect(response).to have_http_status(:ok)
    [ party_path(party), candidacy_path(candidacy), election_path(candidacy.election) ].each do |path|
      expect(page.at_css(%(.place-facts-list a[href="#{path}"]))).to be_present
    end
    expect(response.body).to include("Party line", "Current")
  end

  it "links organizational and personal endorsers on candidacy pages and cards" do
    citizen = create(:citizen)
    create(:endorsement, :major, candidacy: candidacy, endorser: union)
    create(:endorsement, :major, candidacy: candidacy, endorser: citizen)
    BallotLine.create!(candidacy: candidacy, party: party, label: party.name, kind: "party")

    [ candidacy_path(candidacy), candidacy_card_path(candidacy) ].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(page.css(".endorsement-name a").map { it["href"] }).to contain_exactly(organization_path(union), citizen_path(citizen), party_path(party))
    end
  end

  it "retains party filters across pagination and shows a useful empty result" do
    27.times { |index| Party.create!(name: "Calder Coalition #{index.to_s.rjust(2, '0')}", state: calder) }
    get parties_path, params: { state_id: calder.id, q: "Coalition", page: 2 }

    expect(response).to have_http_status(:ok)
    expect(page.css(".list-row-title").length).to eq(2)
    expect(page.css(".pagination a").map { it["href"] }.join).to include("state_id=#{calder.id}", "q=Coalition")

    get organizations_path, params: { q: "No such organization" }
    expect(response.body).to include("No organizations match")
  end
end

require "rails_helper"

RSpec.describe "Endorsement geography and race levels", type: :request do
  include_context "Port Merritt ballot"

  let(:calder) { state.jurisdictionable }
  let(:alder) { alder_county.jurisdictionable }
  let(:league) { create(:organization, name: "Harbor Civic League") }
  let!(:president) { endorsement_for(united_states, "President", code: "POSITION-PRESIDENT") }
  let!(:senator) { endorsement_for(state, "Senator", code: "POSITION-SENATOR") }
  let!(:congress) { endorsement_for(congressional_7, "Representative", code: "POSITION-REPRESENTATIVE") }
  let!(:governor) { endorsement_for(state, "Governor") }
  let!(:assembly) { endorsement_for(assembly_52, "State Representative") }
  let!(:sheriff) { endorsement_for(alder_county, "Sheriff") }
  let!(:mayor) { endorsement_for(port_merritt, "Mayor") }
  let!(:council) { endorsement_for(ward_4, "Council Member") }

  def endorsement_for(jurisdiction, title, code: nil)
    office = create(:office, jurisdiction: jurisdiction, position: create(:position, title: title, entity_code: code))
    create(:endorsement, endorser: league, candidacy: create(:candidacy, race: create_race_for(office)))
  end

  def page
    Nokogiri::HTML(response.body)
  end

  def listed_ids
    page.css("#endorsements-list .list-row").map { it["id"].delete_prefix("list_item_endorsement_") }
  end

  it "composes named scopes across race geography and national, state and local levels" do
    expect(Endorsement.for_races(Race.in_state(calder).national)).to contain_exactly(senator, congress)
    expect(Endorsement.for_races(Race.state_level)).to contain_exactly(governor, assembly)
    expect(Endorsement.for_races(Race.in_county(alder).local)).to contain_exactly(sheriff, mayor, council)
    expect(Endorsement.for_races(Race.national)).to contain_exactly(president, senator, congress)
  end

  it "filters by the race's state rather than the endorser's state" do
    elsewhere = create(:state, :with_jurisdiction, name: "Lakeshore", code: "LS", country: calder.country)
    outside = endorsement_for(elsewhere.jurisdiction, "Governor")
    league.update!(state: elsewhere)

    get endorsements_path, params: { state_id: calder.id }

    expect(response).to have_http_status(:ok)
    expect(listed_ids).to contain_exactly(senator.id, congress.id, governor.id, assembly.id, sheriff.id, mayor.id, council.id)
    expect(listed_ids).not_to include(outside.id)
  end

  it "filters county, municipal and ward races and includes a city's assigned county outside its ancestry" do
    city = create(:municipality, name: "Alder Landing", state: calder, county: alder)
    city_jurisdiction = create(:jurisdiction, jurisdictionable: city, parent: state)
    city_race = endorsement_for(city_jurisdiction, "Mayor")

    get endorsements_path, params: { county_id: alder.id }

    expect(listed_ids).to contain_exactly(sheriff.id, mayor.id, council.id, city_race.id)
    expect(page.at_css('select[name="county_id"] option[selected]')["value"]).to eq(alder.id.to_s)
  end

  it "narrows county options by state and clears a county from another state" do
    elsewhere = create(:state, :with_jurisdiction, name: "Lakeshore", code: "LS", country: calder.country)
    outside_county = create(:county, name: "Pine County", state: elsewhere)

    get endorsements_path, params: { state_id: calder.id, county_id: outside_county.id }

    expect(response).to have_http_status(:ok)
    expect(page.css('select[name="county_id"] option').map { it["value"] }).to eq([ "", alder.id.to_s ])
    expect(page.css('select[name="county_id"] option[selected]')).to be_empty
    expect(listed_ids).to include(governor.id, sheriff.id)

    get endorsements_path
    expect(page.css('select[name="county_id"] option').map { it["value"] }).to include(outside_county.id.to_s)
  end

  it "combines level, geography, search, kind, status and organization filters" do
    create(:endorsement, :withdrawn, candidacy: mayor.candidacy, endorser: create(:organization))
    BallotLine.create!(candidacy: mayor.candidacy, party: Party.create!(name: "Calder Forward", state: calder), kind: "party", label: "Calder Forward")

    get endorsements_path, params: { state_id: calder.id, county_id: alder.id, level: "local", q: "Harbor Civic", kind: "public", status: "current", organization_id: league.id }

    expect(response).to have_http_status(:ok)
    expect(listed_ids).to contain_exactly(sheriff.id, mayor.id, council.id)
    expect(page.at_css('input[name="organization_id"]')["value"]).to eq(league.id.to_s)
    expect(page.at_css('select[name="level"] option[selected]')["value"]).to eq("local")
    expect(page.css("form.filter-form select").map { it["data-action"] }).to all(eq("change->form-submit#submit"))
    expect(page.at_css(".filter-actions a")["href"]).to eq(endorsements_path)
  end

  it "keeps U.S. Senate nomination races national" do
    target = senator.candidacy.office
    nomination = create(:office, position: create(:position, title: Position::NOMINEE_TITLE), jurisdiction: state,
      nominee_for: target, nominating_organization: league, nominee_count: 1)
    primary = create(:endorsement, endorser: league, candidacy: create(:candidacy, race: create_race_for(nomination, :active, kind: "primary")))

    get endorsements_path, params: { state_id: calder.id, level: "national" }

    expect(listed_ids).to contain_exactly(senator.id, congress.id, primary.id)
    get endorsements_path, params: { level: "state" }
    expect(listed_ids).to contain_exactly(governor.id, assembly.id)
  end

  it "keeps geographic filters and organization context while paging" do
    26.times { create(:endorsement, endorser: league, candidacy: create(:candidacy, race: mayor.candidacy.race)) }
    get endorsements_path, params: { state_id: calder.id, county_id: alder.id, level: "local", kind: "public", status: "current", organization_id: league.id, page: 2 }

    expect(response).to have_http_status(:ok)
    expect(listed_ids.size).to eq(4)
    urls = page.css(".pagination a").map { it["href"] }.join
    expect(urls).to include("state_id=#{calder.id}", "county_id=#{alder.id}", "level=local", "kind=public", "status=current", "organization_id=#{league.id}")
  end

  it "shows an empty result for national races within a county rather than guessing district coverage" do
    get endorsements_path, params: { county_id: alder.id, level: "national" }

    expect(response).to have_http_status(:ok)
    expect(listed_ids).to be_empty
    expect(response.body).to include("No endorsements match")
  end
end

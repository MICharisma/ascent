require "rails_helper"

# Results show totals only, residents and visitors apart, from the first saved mountain.
RSpec.describe "Race results", type: :request do
  let(:race) { create(:race, :active) }
  let(:okafor) { create(:candidacy, race: race, citizen: create(:citizen, first_name: "Dana", middle_name: nil, last_name: "Okafor")) }
  let(:lindqvist) { create(:candidacy, race: race, citizen: create(:citizen, first_name: "Theo", middle_name: nil, last_name: "Lindqvist")) }

  def mountain!(ratings, counted_as: "resident")
    voter = create(:voter)
    VoterRaceBaseline.create!(voter: voter, race: race, baseline: 250, counted_as: counted_as)
    ratings.each { |candidacy, rating| Rating.create!(voter: voter, candidacy: candidacy, rating: rating) }
  end

  it "invites the first mountain when there are none, and shows results from the first one" do
    get race_results_path(race)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No mountains yet", "Build your mountain")

    mountain!({ okafor => 400 })
    get race_results_path(race)

    expect(response.body).to include("Approval tally", "Dana Okafor", "100%")
  end

  it "shows residents' approval beside first choice, and keeps visitors apart" do
    6.times { mountain!({ okafor => 300, lindqvist => 450 }) }
    4.times { mountain!({ okafor => 400, lindqvist => 100 }) }
    2.times { mountain!({ lindqvist => 500 }, counted_as: "visitor") }

    get race_results_path(race)

    expect(response.body).to include("Approval tally", "Dana Okafor", "100%", "60%", "Totals only.")
    expect(response.body).to include("Count only each mountain&#39;s highest-rated candidate and Lindqvist leads.")

    get race_results_path(race, group: "visitor")

    # The two visitors approve only Lindqvist; residents' 100% for Okafor stays out of their tally.
    expect(response.body).to match(/Theo Lindqvist<\/td><td class="numeric strong">100%/)
    expect(response.body).to match(/Dana Okafor<\/td><td class="numeric strong">0%/)
  end

  describe "breadcrumbs" do
    let(:country) { create(:country, name: "United States") }
    let(:country_jurisdiction) { create(:jurisdiction, jurisdictionable: country) }
    let(:state) { create(:state, name: "New York", country: country) }
    let(:state_jurisdiction) { create(:jurisdiction, jurisdictionable: state, parent: country_jurisdiction) }
    let(:county) { create(:county, name: "Kings County", state: state) }
    let(:city) { create(:municipality, name: "New York City", state: state) }
    let(:city_jurisdiction) { create(:jurisdiction, jurisdictionable: city, parent: state_jurisdiction) }
    let(:borough) { create(:municipality, name: "Brooklyn", state: state, county: county, parent_municipality: city) }
    let(:borough_jurisdiction) { create(:jurisdiction, jurisdictionable: borough, parent: city_jurisdiction) }

    def breadcrumb_links(label)
      Nokogiri::HTML(response.body).css(%(nav[aria-label="#{label} breadcrumb"] a)).map { [ it.text, it["href"] ] }
    end

    it "shows geography through the election and governance type through the race for either results group" do
      governance_type = create(:governance_type, :executive)
      governing_body = create(:governing_body, name: "Office of the Brooklyn Borough President",
        governance_type: governance_type, jurisdiction: borough_jurisdiction)
      office = create(:office, position: create(:position, title: "Borough President", branch: :executive),
        governing_body: governing_body, jurisdiction: borough_jurisdiction)
      race = create_race_for(office, :active)

      %w[resident visitor].each do |group|
        get race_results_path(race, group: group)

        expect(response).to have_http_status(:ok)
        expect(breadcrumb_links("Location")).to eq([
          [ country.name, country_path(country) ], [ state.name, state_path(state) ],
          [ county.name, county_path(county) ], [ borough.name, municipality_path(borough) ],
          [ race.election.name, election_path(race.election) ]
        ])
        expect(breadcrumb_links("Jurisdiction")).to eq([
          [ governance_type.name, governance_type_path(governance_type) ],
          [ office.position.title, position_path(office.position) ], [ office.name, office_path(office) ],
          [ race.name, race_path(race) ]
        ])
        page = Nokogiri::HTML(response.body)
        expect(page.css('.breadcrumb [aria-current="page"]').map(&:text)).to eq([ "Results" ])
        location = page.at_css('nav[aria-label="Location breadcrumb"]')
        expect(location.css(".breadcrumb-separator").size).to eq(location.css("a").size - 1)
      end
    end

    it "uses a district's recorded containing place without inventing a county for it" do
      district = create(:district, name: "New York Congressional District 10", kind: "congressional district")
      district_jurisdiction = create(:jurisdiction, jurisdictionable: district, parent: state_jurisdiction)
      office = create(:office, position: create(:position, :representative), jurisdiction: district_jurisdiction)
      race = create_race_for(office, :active)

      get race_results_path(race)

      expect(breadcrumb_links("Location")).to eq([
        [ country.name, country_path(country) ], [ state.name, state_path(state) ],
        [ district.name, district_path(district) ], [ race.election.name, election_path(race.election) ]
      ])
      expect(breadcrumb_links("Jurisdiction")).to eq([
        [ office.position.title, position_path(office.position) ], [ office.name, office_path(office) ], [ race.name, race_path(race) ]
      ])
    end

    it "handles a national race with no parent jurisdiction" do
      office = create(:office, position: create(:position, :president), jurisdiction: country_jurisdiction)
      race = create_race_for(office, :active)

      get race_results_path(race)

      expect(breadcrumb_links("Location")).to eq([
        [ country.name, country_path(country) ], [ race.election.name, election_path(race.election) ]
      ])
      expect(breadcrumb_links("Jurisdiction")).to eq([
        [ office.position.title, position_path(office.position) ], [ office.name, office_path(office) ], [ race.name, race_path(race) ]
      ])
    end

    it "shows a root district without inventing geographic parents or an unrecorded governance type" do
      jurisdiction = create(:jurisdiction, jurisdictionable: create(:district, name: "Harbor Ward", kind: "ward"))
      office = create(:office, jurisdiction: jurisdiction)
      race = create_race_for(office, :active)

      get race_results_path(race)

      expect(response).to have_http_status(:ok)
      expect(breadcrumb_links("Location")).to eq([
        [ jurisdiction.name, district_path(jurisdiction.jurisdictionable) ], [ race.election.name, election_path(race.election) ]
      ])
      expect(breadcrumb_links("Jurisdiction")).to eq([
        [ office.position.title, position_path(office.position) ], [ office.name, office_path(office) ], [ race.name, race_path(race) ]
      ])
    end

    it "uses the election's geography when the election covers a broader place than the office" do
      office = create(:office, jurisdiction: borough_jurisdiction)
      election = create(:election, jurisdiction: state_jurisdiction)
      race = create(:race, office: office, election: election)

      get race_results_path(race)

      expect(breadcrumb_links("Location")).to eq([
        [ country.name, country_path(country) ], [ state.name, state_path(state) ],
        [ election.name, election_path(election) ]
      ])
    end
  end
end

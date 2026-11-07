require "rails_helper"

RSpec.describe Seeds::LibraryImporter do
  let(:manifest) { Rails.root.join("spec/fixtures/seed_library/kelles_2024.yml").to_s }
  let(:importer) { described_class.new }

  before { Year.create!(year: 2024, is_even_year: true, is_presidential_year: true) }

  def write_manifest(name, contents)
    path = Rails.root.join("tmp", "seed_library_spec", name)
    FileUtils.mkdir_p(path.dirname)
    path.write(contents)
    path.to_s
  end

  it "rejects the old Person type without creating an identity" do
    legacy = write_manifest("legacy_person.yml", <<~YAML)
      format: micharisma-seeds/v1
      namespace: MIC
      catalog: ASC
      records:
        - type: Person
          code: PERSON-VEGA_MS_2A
          attributes: {last_name: Vega}
    YAML

    expect { importer.call([ legacy ]) }.to raise_error(described_class::Error, /unsupported type Person/)
    expect(Citizen.count).to eq(0)
  end

  it "rejects a candidacy's old person reference" do
    legacy = write_manifest("legacy_reference.yml", File.read(manifest).sub("citizen:", "person:"))

    expect { importer.validate([ legacy ]) }.to raise_error(described_class::Error, /unsupported Candidacy reference person/)
  end

  it "imports one candidacy with a ballot line and a party endorsement for each printed line" do
    report = importer.call([ manifest ])

    candidacy = Candidacy.find_by!(entity_code: "CANDIDACY-USA-NY-ASSEMBLY-AD_125-2024_GENERAL-KELLES_AN_2R")
    expect(candidacy.citizen).to have_attributes(username: "kelles_an_2r", username_status: "provisional", email: nil)
    expect(candidacy.ballot_lines.map { |line| [ line.label, line.kind, line.party.entity_code ] }).to eq([
      [ "Democratic", "party", "PARTY-USA-NY-DEMOCRATIC" ],
      [ "Working Families", "party", "PARTY-USA-NY-WORKING_FAMILIES" ]
    ])
    expect(candidacy.endorsements.map { |endorsement| [ endorsement.kind, endorsement.endorser.name ] })
      .to contain_exactly([ "ballot_line", "Democratic" ], [ "ballot_line", "Working Families" ])
    expect(candidacy.ballot_labels).to eq("Democratic; Working Families")

    race = candidacy.race
    expect(race).to have_attributes(entity_code: "RACE-USA-NY-ASSEMBLY-AD_125-2024_GENERAL", certification_status: "certified", status: "completed")
    expect(race.election).to have_attributes(entity_code: "ELECTION-USA-NY-ASSEMBLY-AD_125-2024_GENERAL", year: Year.find_by!(year: 2024))
    expect(race.office).to have_attributes(seat_code: "AD_125", name: "State Representative in New York, District 125")

    district = District.find_by!(entity_code: "DISTRICT-USA-NY-ASSEMBLY-AD_125")
    expect(district.jurisdiction.parent.jurisdictionable).to eq(State.find_by!(entity_code: "STATE-USA-NY"))
    expect(State.find_by!(code: "NY").jurisdiction.parent.jurisdictionable).to eq(Country.find_by!(code: "US"))

    expect(report[:created].size).to eq(11)
    expect(report[:ballot_lines_added].size).to eq(2)
    expect(EntityCode.where(catalog: "ASC").count).to eq(11)
    expect(EntityCode.find_by!(code: "CITIZEN-KELLES_AN_2R").record).to eq(candidacy.citizen)
  end

  it "changes nothing when the same manifest is imported again" do
    importer.call([ manifest ])
    counts = -> { [ Candidacy, BallotLine, Endorsement, Party, Jurisdiction, EntityCode ].map(&:count) }

    expect { importer.call([ manifest ]) }.not_to change(&counts)
    expect(importer.report[:unchanged].size).to eq(11)
    expect(importer.report[:conflicts]).to be_empty
  end

  it "adopts uncoded records created by the reference seeders" do
    country = Country.create!(code: "US", name: "United States")
    position = Position.create!(title: "State Representative", branch: :legislative)

    importer.call([ manifest ])

    expect(country.reload.entity_code).to eq("COUNTRY-USA")
    expect(position.reload.entity_code).to eq("POSITION-STATE_REPRESENTATIVE")
    expect(Country.count).to eq(1)
  end

  # Ohio has a Washington Township in dozens of counties; each is its own place with its own URI.
  it "keeps records with different URIs apart even when their names match" do
    townships = write_manifest("townships.yml", <<~YAML)
      format: micharisma-seeds/v1
      namespace: MIC
      catalog: ASC
      records:
        - type: Country
          code: COUNTRY-USA
          attributes: { code: US, name: United States }
        - type: State
          code: STATE-USA-OH
          attributes: { code: OH, name: Ohio }
          references: { country: COUNTRY-USA }
        - type: County
          code: COUNTY-USA-OH-HOLMES
          attributes: { name: Holmes County }
          references: { state: STATE-USA-OH }
        - type: County
          code: COUNTY-USA-OH-MUSKINGUM
          attributes: { name: Muskingum County }
          references: { state: STATE-USA-OH }
        - type: Municipality
          code: MUNICIPALITY-USA-OH-WASHINGTON_TOWNSHIP_HOLMES
          attributes: { name: Washington Township }
          references: { state: STATE-USA-OH, county: COUNTY-USA-OH-HOLMES }
        - type: Municipality
          code: MUNICIPALITY-USA-OH-WASHINGTON_TOWNSHIP_MUSKINGUM
          attributes: { name: Washington Township }
          references: { state: STATE-USA-OH, county: COUNTY-USA-OH-MUSKINGUM }
    YAML

    importer.call([ townships ])

    expect(importer.report[:conflicts]).to be_empty
    expect(importer.report[:aliases_added]).to be_empty
    expect(Municipality.where(name: "Washington Township").map { it.county.name }).to contain_exactly("Holmes County", "Muskingum County")
  end

  # A borough sits inside its city, whose jurisdiction spans several counties, and shares its borders
  # with one county; it nests under the city even when listed before it.
  it "nests a town inside the town it names as its parent" do
    boroughs = write_manifest("boroughs.yml", <<~YAML)
      format: micharisma-seeds/v1
      namespace: MIC
      catalog: ASC
      records:
        - type: Country
          code: COUNTRY-USA
          attributes: { code: US, name: United States }
        - type: State
          code: STATE-USA-NY
          attributes: { code: NY, name: New York }
          references: { country: COUNTRY-USA }
        - type: County
          code: COUNTY-USA-NY-KINGS
          attributes: { name: Kings County }
          references: { state: STATE-USA-NY }
        - type: Municipality
          code: MUNICIPALITY-USA-NY-BROOKLYN
          attributes: { name: Brooklyn }
          references: { state: STATE-USA-NY, county: COUNTY-USA-NY-KINGS, parent_municipality: MUNICIPALITY-USA-NY-NEW_YORK }
        - type: Municipality
          code: MUNICIPALITY-USA-NY-NEW_YORK
          attributes: { name: New York }
          references: { state: STATE-USA-NY }
    YAML

    importer.call([ boroughs ])

    brooklyn = Municipality.find_by!(name: "Brooklyn")
    new_york = Municipality.find_by!(name: "New York")
    expect(brooklyn).to have_attributes(parent_municipality: new_york, county: County.find_by!(name: "Kings County"))
    expect(brooklyn.jurisdiction.parent).to eq(new_york.jurisdiction)
    expect(new_york.jurisdiction.parent.jurisdictionable).to eq(State.find_by!(code: "NY"))
  end

  it "claims an uncoded place only once, leaving a second URI its own record" do
    ohio = State.create!(code: "OH", name: "Ohio", country: Country.create!(code: "US", name: "United States"))
    seeded = Municipality.create!(name: "Washington Township", state: ohio)
    townships = write_manifest("townships.yml", <<~YAML)
      format: micharisma-seeds/v1
      namespace: MIC
      catalog: ASC
      records:
        - type: Country
          code: COUNTRY-USA
          attributes: { code: US, name: United States }
        - type: State
          code: STATE-USA-OH
          attributes: { code: OH, name: Ohio }
          references: { country: COUNTRY-USA }
        - type: Municipality
          code: MUNICIPALITY-USA-OH-WASHINGTON_TOWNSHIP_HOLMES
          attributes: { name: Washington Township }
          references: { state: STATE-USA-OH }
        - type: Municipality
          code: MUNICIPALITY-USA-OH-WASHINGTON_TOWNSHIP_MUSKINGUM
          attributes: { name: Washington Township }
          references: { state: STATE-USA-OH }
    YAML

    importer.call([ townships ])

    expect(seeded.reload.entity_code).to eq("MUNICIPALITY-USA-OH-WASHINGTON_TOWNSHIP_HOLMES")
    expect(Municipality.find_by!(entity_code: "MUNICIPALITY-USA-OH-WASHINGTON_TOWNSHIP_MUSKINGUM")).not_to eq(seeded)
  end

  describe "a citizen's name code without its disambiguator" do
    def citizens(*codes)
      write_manifest("citizens.yml", <<~YAML)
        format: micharisma-seeds/v1
        namespace: MIC
        catalog: ASC
        records:
        #{codes.map { |code| "  - {type: Citizen, code: CITIZEN-#{code}, attributes: {username: #{code.downcase}, username_status: provisional, first_name: Letitia, last_name: James}}" }.join("\n")}
      YAML
    end

    it "names the one citizen whose code adds a disambiguator to it" do
      importer.call([ citizens("JAMES_LT_6J") ])

      expect(importer.resolve_code("Citizen", "CITIZEN-JAMES_LT")).to eq(Citizen.find_by!(username: "james_lt_6j"))
      expect(importer.resolve_code("Citizen", "MIC-ASC-CITIZEN-JAMES_LT")).to eq(Citizen.find_by!(username: "james_lt_6j"))
      expect(importer.resolve_code("Citizen", "CITIZEN-JAMES")).to be_nil
    end

    it "asks for the full code when two citizens share the name code" do
      importer.call([ citizens("JAMES_LT_6J", "JAMES_LT_4K") ])

      expect { importer.resolve_code("Citizen", "CITIZEN-JAMES_LT") }
        .to raise_error(described_class::Error, "CITIZEN-JAMES_LT could be CITIZEN-JAMES_LT_4K or CITIZEN-JAMES_LT_6J; use the full code")
    end

    it "rejects a bare name code on a Citizen definition instead of silently merging" do
      importer.call([ citizens("JAMES_LT_6J") ])

      expect { importer.validate([ citizens("JAMES_LT") ]) }
        .to raise_error(described_class::Error, /Citizen definition CITIZEN-JAMES_LT requires a disambiguator; bare name codes are allowed only as references/)
      expect { importer.call([ citizens("JAMES_LT") ]) }
        .to raise_error(described_class::Error, /Citizen definition CITIZEN-JAMES_LT requires a disambiguator/)
    end

    it "holds only a provisional username to its code" do
      citizen = ->(status) do
        write_manifest("citizen.yml", <<~YAML)
          format: micharisma-seeds/v1
          namespace: MIC
          catalog: ASC
          records:
            - {type: Citizen, code: CITIZEN-JAMES_LT_6J, attributes: {username: tishjames, username_status: #{status}, first_name: Letitia, last_name: James}}
        YAML
      end

      expect { importer.validate([ citizen.call("provisional") ]) }
        .to raise_error(described_class::Error, /Citizen CITIZEN-JAMES_LT_6J provisional username "tishjames" does not match its code/)
      importer.call([ citizen.call("verified") ])
      expect(Citizen.find_by!(entity_code: "CITIZEN-JAMES_LT_6J")).to have_attributes(username: "tishjames", username_status: "verified")
    end
  end

  describe "nominations and organizations" do
    let(:primary) do
      write_manifest("primary.yml", <<~YAML)
        format: micharisma-seeds/v1
        namespace: MIC
        catalog: ASC
        records:
          - {type: Country, code: COUNTRY-USA, attributes: {code: US, name: United States}}
          - {type: State, code: STATE-USA-GA, attributes: {code: GA, name: Georgia}, references: {country: COUNTRY-USA}}
          - {type: District, code: DISTRICT-USA-GA-CONGRESS-CD_5, attributes: {name: Georgia Congressional District 5, kind: congressional district}, scope: {state: STATE-USA-GA}}
          - {type: Position, code: POSITION-REPRESENTATIVE, attributes: {title: Representative, branch: legislative}}
          - {type: Position, code: POSITION-NOMINEE, attributes: {title: Nominee, branch: legislative}}
          - {type: Party, code: PARTY-USA-GA-DEMOCRATIC, attributes: {name: Democratic Party}, references: {state: STATE-USA-GA}}
          - {type: Organization, code: ORGANIZATION-USA-GA-TOP_TWO_PRIMARY, attributes: {name: Georgia Top-Two Primary, kind: nonpartisan_primary}, references: {state: STATE-USA-GA}}
          - type: Office
            code: OFFICE-USA-GA-CONGRESS-CD_5
            attributes: {seat_code: CD_5, is_active: true}
            references: {position: POSITION-REPRESENTATIVE, jurisdiction: DISTRICT-USA-GA-CONGRESS-CD_5}
          - type: Office
            code: OFFICE-USA-GA-CONGRESS-CD_5-NOMINEE_DEMOCRATIC
            attributes: {nominee_count: 1, is_active: true}
            references: {position: POSITION-NOMINEE, jurisdiction: DISTRICT-USA-GA-CONGRESS-CD_5, nominee_for: OFFICE-USA-GA-CONGRESS-CD_5, nominating_organization: PARTY-USA-GA-DEMOCRATIC}
          - type: Election
            code: ELECTION-USA-GA-2026_PRIMARY
            attributes: {name: Georgia Primary Election 2026, kind: primary, election_date: "2026-05-19", status: completed, is_mock: false, is_historical: false}
            references: {jurisdiction: STATE-USA-GA, year: YEAR-2024}
          - type: Race
            code: RACE-USA-GA-CONGRESS-CD_5-NOMINEE_DEMOCRATIC-2026_PRIMARY
            attributes: {status: completed}
            references: {election: ELECTION-USA-GA-2026_PRIMARY, office: OFFICE-USA-GA-CONGRESS-CD_5-NOMINEE_DEMOCRATIC}
          - type: Channel
            code: CHANNEL-WEB-GEORGIADEMOCRAT_EXAMPLE_COM
            attributes: {platform: website, handle: georgiademocrat.example.com, official: true}
            references: {owner: PARTY-USA-GA-DEMOCRATIC}
      YAML
    end

    it "imports a district's nomination race into the statewide primary" do
      importer.call([ primary ])

      race = Race.find_by!(entity_code: "RACE-USA-GA-CONGRESS-CD_5-NOMINEE_DEMOCRATIC-2026_PRIMARY")
      expect(race.office).to have_attributes(nomination?: true, nominee_count: 1, nominating_organization: Party.find_by!(name: "Democratic Party"))
      expect(race.office.nominee_for.entity_code).to eq("OFFICE-USA-GA-CONGRESS-CD_5")
      expect(race.election.jurisdiction.jurisdictionable.name).to eq("Georgia")
      expect(Organization.find_by!(entity_code: "ORGANIZATION-USA-GA-TOP_TWO_PRIMARY")).to have_attributes(kind: "nonpartisan_primary")
      expect(Channel.find_by!(entity_code: "CHANNEL-WEB-GEORGIADEMOCRAT_EXAMPLE_COM").owner).to be_a(Party)
      expect(importer.resolve_code("Organization", "PARTY-USA-GA-DEMOCRATIC")).to be_a(Party)
    end

    it "refuses an organization's code where a party is required" do
      importer.call([ primary ])

      expect { importer.resolve_code("Party", "ORGANIZATION-USA-GA-TOP_TWO_PRIMARY") }
        .to raise_error(described_class::Error, "ORGANIZATION-USA-GA-TOP_TWO_PRIMARY identifies Organization, not Party")
    end

    describe "primary candidates in the general" do
      let(:race) { "RACE-USA-GA-CONGRESS-CD_5-2026_GENERAL" }

      def candidacy_record(citizen, race_code, participation = "active")
        <<~YAML.indent(2)
          - type: Candidacy
            code: CANDIDACY-#{race_code.delete_prefix("RACE-")}-#{citizen}
            attributes: {status: active, participation: #{participation}}
            references: {race: #{race_code}, citizen: CITIZEN-#{citizen}}
        YAML
      end

      let(:field) do
        write_manifest("field.yml", <<~YAML + candidacy_record("BELL_TS_2A", "RACE-USA-GA-CONGRESS-CD_5-NOMINEE_DEMOCRATIC-2026_PRIMARY") + candidacy_record("ODOM_RN_3B", "RACE-USA-GA-CONGRESS-CD_5-NOMINEE_DEMOCRATIC-2026_PRIMARY") + candidacy_record("BELL_TS_2A", race))
          format: micharisma-seeds/v1
          namespace: MIC
          catalog: ASC
          records:
            - {type: Citizen, code: CITIZEN-BELL_TS_2A, attributes: {username: bell_ts_2a, username_status: provisional, first_name: Tasha, last_name: Bell}}
            - {type: Citizen, code: CITIZEN-ODOM_RN_3B, attributes: {username: odom_rn_3b, username_status: provisional, first_name: Ronan, last_name: Odom}}
            - type: Election
              code: ELECTION-USA-GA-2026_GENERAL
              attributes: {name: Georgia General Election 2026, kind: general, election_date: "2026-11-03", status: upcoming, is_mock: false, is_historical: false}
              references: {jurisdiction: STATE-USA-GA, year: YEAR-2024}
            - type: Race
              code: #{race}
              attributes: {status: upcoming}
              references: {election: ELECTION-USA-GA-2026_GENERAL, office: OFFICE-USA-GA-CONGRESS-CD_5}
        YAML
      end

      it "adds the primary's other candidates to the general off the ballot" do
        importer.call([ primary, field ])

        general = Race.find_by!(entity_code: race)
        expect(general.status).to eq("active")
        expect(general.election.status).to eq("upcoming")
        expect(general.candidacies.map { [ it.citizen.last_name, it.participation, it.entity_code.present? ] })
          .to contain_exactly([ "Bell", "active", true ], [ "Odom", "off_ballot", false ])
        expect(importer.report[:primary_candidates_added]).to contain_exactly("Ronan Odom for Representative")
        expect { importer.call([ primary, field ]) }.not_to change(Candidacy, :count)
        expect(importer.report[:conflicts]).to be_empty
      end

      it "lets the data place a primary candidate on the general's ballot, keeping their candidacy" do
        importer.call([ primary, field ])
        off_ballot = Candidacy.find_by!(race: Race.find_by!(entity_code: race), citizen: Citizen.find_by!(last_name: "Odom"))
        independent = write_manifest("independent.yml", "format: micharisma-seeds/v1\nnamespace: MIC\ncatalog: ASC\nrecords:\n" + candidacy_record("ODOM_RN_3B", race))

        report = described_class.new.call([ primary, field, independent ])

        expect(off_ballot.reload).to have_attributes(entity_code: "CANDIDACY-USA-GA-CONGRESS-CD_5-2026_GENERAL-ODOM_RN_3B", participation: "active", primary_candidacy: nil)
        expect(report[:conflicts]).to be_empty
        expect(report[:primary_candidates_added]).to be_empty
      end

      it "does not take a primary candidacy from a manifest" do
        bad = write_manifest("bad.yml", File.read(field).sub("references: {race: #{race}, citizen: CITIZEN-BELL_TS_2A}", "references: {race: #{race}, citizen: CITIZEN-BELL_TS_2A, primary_candidacy: CANDIDACY-USA-GA-CONGRESS-CD_5-NOMINEE_DEMOCRATIC-2026_PRIMARY-BELL_TS_2A}"))

        expect { importer.call([ primary, bad ]) }.to raise_error(described_class::Error, /unsupported Candidacy reference primary_candidacy/)
      end
    end
  end

  it "reports a differing existing value instead of overwriting it" do
    importer.call([ manifest ])
    Race.find_by!(entity_code: "RACE-USA-NY-ASSEMBLY-AD_125-2024_GENERAL").update!(certification_status: "tentative")

    importer.call([ manifest ])

    expect(Race.find_by!(entity_code: "RACE-USA-NY-ASSEMBLY-AD_125-2024_GENERAL").certification_status).to eq("tentative")
    expect(importer.report[:conflicts]).to contain_exactly(
      a_hash_including(code: "RACE-USA-NY-ASSEMBLY-AD_125-2024_GENERAL",
        differences: { "certification_status" => { existing: "tentative", incoming: "certified" } })
    )
  end

  it "resolves a registered alias to the same record" do
    importer.call([ manifest ])
    aliased = write_manifest("alias.yml", <<~YAML)
      format: micharisma-seeds/v1
      namespace: MIC
      catalog: ASC
      records:
        - type: Citizen
          code: CITIZEN-KELLES_AN_2R
          aliases: [CITIZEN-KELLES_ANNA_NY_AD_125]
    YAML

    importer.call([ aliased ])

    expect(importer.report[:aliases_added]).to eq([ "CITIZEN-KELLES_ANNA_NY_AD_125" ])
    expect(importer.resolve_code("Citizen", "MIC-ASC-CITIZEN-KELLES_ANNA_NY_AD_125")).to eq(Citizen.find_by!(username: "kelles_an_2r"))
  end

  it "writes nothing for a record until its dependencies exist" do
    district = write_manifest("a_district.yml", <<~YAML)
      format: micharisma-seeds/v1
      namespace: MIC
      catalog: ASC
      scope:
        state: STATE-USA-NY
      records:
        - type: District
          code: DISTRICT-USA-NY-ASSEMBLY-AD_125
          attributes:
            name: New York Assembly District 125
            kind: assembly district
    YAML
    state = write_manifest("b_state.yml", <<~YAML)
      format: micharisma-seeds/v1
      namespace: MIC
      catalog: ASC
      records:
        - type: Country
          code: COUNTRY-USA
          attributes: {code: US, name: United States}
        - type: State
          code: STATE-USA-NY
          attributes: {code: NY, name: New York}
          references: {country: COUNTRY-USA}
    YAML

    report = importer.call([ district, state ])

    expect(report[:created]).to eq(%w[COUNTRY-USA STATE-USA-NY DISTRICT-USA-NY-ASSEMBLY-AD_125])
    expect(report[:unchanged]).to be_empty
    expect(District.sole.jurisdiction.parent.jurisdictionable).to eq(State.sole)
  end

  it "rejects attributes that are not part of the catalog contract" do
    invalid = write_manifest("invalid.yml", <<~YAML)
      format: micharisma-seeds/v1
      namespace: MIC
      catalog: ASC
      records:
        - type: Candidacy
          code: CANDIDACY-EXAMPLE
          attributes:
            party_affiliation: Democratic
    YAML

    expect { importer.validate([ invalid ]) }.to raise_error(described_class::Error, /unsupported Candidacy attribute party_affiliation/)
  end

  it "refuses entity-sequence lookups until their recipes are installed" do
    sequenced = write_manifest("sequenced.yml", <<~YAML)
      format: micharisma-seeds/v1
      namespace: MIC
      catalog: ASC
      entity_sequence: "10_01"
      records:
        - type: Citizen
          code: CITIZEN-EXAMPLE_2A
    YAML

    expect { importer.validate([ sequenced ]) }.to raise_error(StandardError, /sequence/i)
  end
end

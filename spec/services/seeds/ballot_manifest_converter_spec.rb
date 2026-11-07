require "rails_helper"

RSpec.describe Seeds::BallotManifestConverter do
  let(:root) { Rails.root.join("tmp", "ballot_manifest_converter_spec") }

  def row(office, district, name, party, status: "certified", level: nil, county: "", jurisdiction: "", notes: "")
    {
      "election_date" => "2026-11-03", "state" => "NY", "office" => office, "district" => district,
      "office_level" => level || (district.empty? ? "state" : "federal"), "candidate_name" => name, "party" => party,
      "incumbent" => "", "status" => status, "source_url" => "https://elections.ny.gov/certification",
      "retrieved_on" => "2026-10-01", "vote_for" => "1", "notes" => notes, "county" => county, "jurisdiction" => jurisdiction
    }
  end

  def write(relative, contents)
    path = root.join(relative)
    FileUtils.mkdir_p(path.dirname)
    path.write(contents)
  end

  # The catalog's coded Positions, which every converted office names by code.
  def write_foundation
    positions = {
      "GOVERNOR" => "Governor", "REPRESENTATIVE" => "Representative", "ATTORNEY_GENERAL" => "Attorney General",
      "STATE_SENATOR" => "State Senator", "APPELLATE_JUDGE" => "Appellate Judge", "SHERIFF" => "Sheriff",
      "TOWN_SUPERVISOR" => "Town Supervisor", "TOWN_CLERK" => "Town Clerk", "COUNCIL_MEMBER" => "Council Member",
      "MAYOR" => "Mayor", "SCHOOL_BOARD_MEMBER" => "School Board Member"
    }.map { |suffix, title| { "type" => "Position", "code" => "POSITION-#{suffix}", "attributes" => { "title" => title } } }
    write("manifests/foundation.yml", {
      "format" => "micharisma-seeds/v1", "namespace" => "MIC", "catalog" => "ASC",
      "records" => [ { "type" => "Country", "code" => "COUNTRY-USA", "attributes" => { "code" => "US", "name" => "United States" } } ] + positions
    }.to_yaml)
  end

  def write_offices(offices)
    write("conversion/2026/new_york/offices.yml", offices.to_yaml)
  end

  before do
    FileUtils.rm_rf(root)
    write("us_states.yml", { "states" => [ { "code" => "NY", "name" => "New York", "country_code" => "US" } ] }.to_yaml)
    write_foundation
    write_offices("Sheriff" => "POSITION-SHERIFF", "Town Supervisor" => "POSITION-TOWN_SUPERVISOR", "Town Clerk" => "POSITION-TOWN_CLERK",
                  "School Board - Special" => "POSITION-SCHOOL_BOARD_MEMBER")
    write("races/2026/new_york/state/governor.yml", [
      row("Governor", "", "Kathy Hochul", "Democratic"),
      row("Governor", "", "Kathy Hochul", "Working Families")
    ].to_yaml)
    write("races/2026/new_york/federal/representative_in_congress.yml", [
      row("Representative in Congress", "15", "Ritchie J. Torres", "Democratic"),
      row("Representative in Congress", "15", "Jose Vega", "Speak The Truth")
    ].to_yaml)
    write("races/2026/new_york/conflicts.csv", <<~CSV)
      state,office,district,candidate_name,field,value_a,source_a,value_b,source_b,note
      NY,Governor,,Paul Mailhot,presence,not listed,https://elections.ny.gov,listed; balloted=Write-in,https://www.thegreenpapers.com,Green Papers lists this citizen
      NY,Representative in Congress,15,Ritchie J. Torres,candidate_name,Ritchie J. Torres,https://elections.ny.gov,"TORRES, RITCHIE",https://www.fec.gov,name form differs
    CSV
    write("conversion/2026/new_york/rules.yml", {
      "parties" => [
        { "code" => "DEMOCRATIC", "name" => "Democratic", "labels" => [ "Democratic" ] },
        { "code" => "WORKING_FAMILIES", "name" => "Working Families", "labels" => [ "Working Families" ] }
      ],
      "other_labels" => "designation",
      "unprinted_labels" => [ "Nonpartisan" ],
      "special_elections" => [ "- Special\\z" ]
    }.to_yaml)
  end

  after { FileUtils.rm_rf(root) }

  def convert
    described_class.new(state_dir: "new_york", selection: :all, root: root).call
  end

  # A username is the surname, the given name's first letter and next consonant, and a disambiguator.
  def username_like(base)
    /\A#{base}_[2-9][a-hj-np-z]\z/
  end

  it "writes manifests that the importer turns into races, ballot lines, and endorsements" do
    convert
    Year.create!(year: 2026, is_even_year: true, is_presidential_year: false)

    report = Seeds::LibraryImporter.new.call(Dir.glob(root.join("manifests/**/*.yml").to_s))

    expect(report[:conflicts]).to be_empty
    governor = Race.find_by!(entity_code: "RACE-USA-NY-GOVERNOR-2026_GENERAL")
    expect(governor.election).to have_attributes(entity_code: "ELECTION-USA-NY-2026_GENERAL", name: "New York General Election 2026")
    expect(governor.certification_status).to eq("certified")
    hochul = governor.candidacies.joins(:citizen).find_by!(citizens: { last_name: "Hochul" })
    expect(hochul.citizen.username).to match(username_like("hochul_kt"))
    expect(hochul.citizen.entity_code).to eq("CITIZEN-#{hochul.citizen.username.upcase}")
    expect(hochul.ballot_labels).to eq("Democratic; Working Families")
    expect(hochul.endorsements.map { |endorsement| endorsement.endorser.entity_code })
      .to contain_exactly("PARTY-USA-NY-DEMOCRATIC", "PARTY-USA-NY-WORKING_FAMILIES")

    write_in = governor.candidacies.joins(:citizen).find_by!(citizens: { last_name: "Mailhot" })
    expect(write_in).to have_attributes(participation: "off_ballot")
    expect(write_in.ballot_lines).to be_empty

    house = Race.find_by!(entity_code: "RACE-USA-NY-CONGRESS-CD_15-2026_GENERAL")
    expect(house.office).to have_attributes(seat_code: "CD_15", jurisdiction: District.find_by!(name: "New York Congressional District 15").jurisdiction)
    vega = house.candidacies.joins(:citizen).find_by!(citizens: { last_name: "Vega" })
    expect(vega.ballot_lines.sole).to have_attributes(label: "Speak The Truth", kind: "designation", party: nil)
    expect(vega.endorsements).to be_empty
  end

  it "reports its judgments and keeps issued usernames on later runs" do
    convert
    usernames = YAML.load_file(root.join("conversion/2026/new_york/usernames.yml"))
    torres = usernames.fetch("Representative in Congress|15|Ritchie J. Torres")
    expect(torres).to match(username_like("torres_rt"))

    spellings = YAML.load_file(root.join("conversion/2026/new_york/name_spellings.yml"))
    expect(spellings.sole).to include("username" => torres, "other_spelling" => "TORRES, RITCHIE")

    judgments = root.join("conversion/2026/new_york/judgments.md").read
    expect(judgments).to include("Paul Mailhot (Governor)", "- designation: Speak The Truth", "- party: Democratic, Working Families")

    usernames["Representative in Congress|15|Ritchie J. Torres"] = "torres_rt_9z"
    root.join("conversion/2026/new_york/usernames.yml").write(usernames.to_yaml)
    summary = convert

    expect(summary[:usernames_issued]).to eq(0)
    expect(root.join("manifests/2026/new_york/congress.yml").read).to include("CITIZEN-TORRES_RT_9Z")
  end

  it "places local contests in their town, county, or a district for several places" do
    write("races/2026/new_york/local/erie.yml", [
      row("Sheriff", "", "John C. Garcia", "Republican", level: "local", county: "Erie"),
      row("Town Supervisor", "Town of Aurora", "James J. Bach", "Nonpartisan", level: "local", county: "Erie", jurisdiction: "Aurora"),
      row("School Board - Special", "Seat 2", "Ann Lee", "Nonpartisan", level: "local", county: "Erie; Niagara")
    ].to_yaml)

    convert
    Year.create!(year: 2026, is_even_year: true, is_presidential_year: false)
    report = Seeds::LibraryImporter.new.call(Dir.glob(root.join("manifests/**/*.yml").to_s))

    expect(report[:conflicts]).to be_empty
    sheriff = Race.find_by!(entity_code: "RACE-USA-NY-COUNTY_ERIE-SHERIFF-2026_GENERAL")
    expect(sheriff.office.jurisdiction.jurisdictionable).to eq(County.find_by!(name: "Erie County"))
    expect(sheriff.candidacies.sole.citizen.username).to match(username_like("garcia_jh"))

    aurora = Municipality.find_by!(name: "Aurora")
    expect(aurora.county.name).to eq("Erie County")
    # The district column prints the town itself, so it names no seat.
    supervisor = Race.find_by!(entity_code: "RACE-USA-NY-AURORA-TOWN_SUPERVISOR-2026_GENERAL")
    expect(supervisor.office).to have_attributes(seat_code: nil, jurisdiction: aurora.jurisdiction)
    expect(supervisor.candidacies.sole.ballot_lines).to be_empty

    school = Race.find_by!(entity_code: "RACE-USA-NY-SCHOOL_BOARD_MEMBER-ERIE_COUNTY_NIAGARA_COUNTY-SEAT_2-2026_SPECIAL")
    expect(school.election).to have_attributes(kind: "special", name: "New York School Board Member (Erie County, Niagara County) Special Election 2026")
    expect(school.office.position.entity_code).to eq("POSITION-SCHOOL_BOARD_MEMBER")
    expect(Position.pluck(:title)).not_to include("School Board - Special")
  end

  it "shares one Position among titles that print a place, seat, or term" do
    write_offices("SUPERVISOR-BEDFORD" => { "position" => "POSITION-TOWN_SUPERVISOR", "town" => "Town of Bedford" },
                  "Ward 1 Council Member" => { "position" => "POSITION-COUNCIL_MEMBER", "seat" => "Ward 1" },
                  "COUNCILMEMBER-UNEXP.-WARD 1" => { "position" => "POSITION-COUNCIL_MEMBER", "seat" => "Ward 1", "term" => "Unexpired Term" },
                  "Mayor - Alberta" => "POSITION-MAYOR")
    write("races/2026/new_york/local/westchester.yml", [
      row("SUPERVISOR-BEDFORD", "", "Ann Lee", "Nonpartisan", level: "local", county: "Westchester"),
      row("Ward 1 Council Member", "Town of Queensbury Ward 1", "Bo Diaz", "Nonpartisan", level: "local", county: "Warren", jurisdiction: "Town of Queensbury"),
      row("COUNCILMEMBER-UNEXP.-WARD 1", "", "Cy Park", "Nonpartisan", level: "local", county: "Warren", jurisdiction: "Town of Queensbury"),
      row("Mayor - Alberta", "Town of Alberta", "Di Fox", "Nonpartisan", level: "local", county: "BRUNSWICK COUNTY", jurisdiction: "BRUNSWICK COUNTY")
    ].to_yaml)

    convert
    Year.create!(year: 2026, is_even_year: true, is_presidential_year: false)
    Seeds::LibraryImporter.new.call(Dir.glob(root.join("manifests/**/*.yml").to_s))

    expect(Race.find_by!(entity_code: "RACE-USA-NY-TOWN_OF_BEDFORD-TOWN_SUPERVISOR-2026_GENERAL").office.jurisdiction.name).to eq("Town of Bedford")
    regular, unexpired = Race.where(entity_code: [ "RACE-USA-NY-TOWN_OF_QUEENSBURY-COUNCIL_MEMBER-WARD_1-2026_GENERAL",
                                                   "RACE-USA-NY-TOWN_OF_QUEENSBURY-COUNCIL_MEMBER-WARD_1-UNEXPIRED_TERM-2026_GENERAL" ]).order(:entity_code)
    expect(unexpired.office).to eq(regular.office)
    # A town printed in the district column of a county-wide row is the office's place.
    mayor = Race.find_by!(entity_code: "RACE-USA-NY-TOWN_OF_ALBERTA-MAYOR-2026_GENERAL").office
    expect(mayor.jurisdiction.jurisdictionable).to have_attributes(name: "Town of Alberta", county: County.find_by!(name: "Brunswick County"))
    expect(Office.joins(:position).where(positions: { title: "Council Member" }).count).to eq(1)
  end

  it "refuses a local title offices.yml leaves out" do
    write("races/2026/new_york/local/erie.yml", [ row("Dog Catcher", "", "Ann Lee", "Nonpartisan", level: "local", county: "Erie") ].to_yaml)

    expect { convert }.to raise_error(Seeds::BallotManifestConverter::Error, /"Dog Catcher" is missing from .*offices.yml/)
  end

  it "refuses to merge two printed contests into one race" do
    write_offices("Council Member" => "POSITION-COUNCIL_MEMBER", "Council Member (to fill vacancy)" => "POSITION-COUNCIL_MEMBER")
    write("races/2026/new_york/local/erie.yml", [
      row("Council Member", "", "Ann Lee", "Nonpartisan", level: "local", county: "Erie", jurisdiction: "Aurora"),
      row("Council Member (to fill vacancy)", "", "Bo Diaz", "Nonpartisan", level: "local", county: "Erie", jurisdiction: "Aurora")
    ].to_yaml)

    expect { convert }.to raise_error(Seeds::BallotManifestConverter::Error, /would share RACE-USA-NY-AURORA-COUNCIL_MEMBER-2026_GENERAL; give each its own seat or term/)
  end

  # Connecticut's towns belong to planning regions rather than the counties its ballots still print.
  # This made-up region stands in for one in the New York fixture.
  describe "a state that lists county-equivalents" do
    before do
      write("conversion/2026/new_york/county_equivalents.yml", { "counties" => [
        { "code" => "COUNTY-USA-NY-SOUTHTOWNS", "name" => "Southtowns Planning Region", "towns" => [ "Aurora", "Holland" ] }
      ] }.to_yaml)
    end

    it "takes each town's county from the list instead of the printed county" do
      write("races/2026/new_york/local/erie.yml", [
        row("Town Supervisor", "Town of Aurora", "James J. Bach", "Nonpartisan", level: "local", county: "Erie", jurisdiction: "Aurora"),
        row("Town Clerk", "", "Dana Wu", "Nonpartisan", level: "local", county: "Erie", jurisdiction: "Holland")
      ].to_yaml)

      convert
      Year.create!(year: 2026, is_even_year: true, is_presidential_year: false)
      report = Seeds::LibraryImporter.new.call(Dir.glob(root.join("manifests/**/*.yml").to_s))

      expect(report[:conflicts]).to be_empty
      expect(Municipality.find_by!(name: "Aurora").county.name).to eq("Southtowns Planning Region")
      expect(Municipality.find_by!(name: "Holland").county.entity_code).to eq("COUNTY-USA-NY-SOUTHTOWNS")
      expect(County.where(name: "Erie County")).not_to exist
      expect(root.join("manifests/2026/new_york/local/southtowns.yml")).to exist
      expect(Race.find_by!(entity_code: "RACE-USA-NY-AURORA-TOWN_SUPERVISOR-2026_GENERAL")).to be_present
    end

    it "refuses a town the list leaves out" do
      write("races/2026/new_york/local/erie.yml", [
        row("Town Supervisor", "Town of Elma", "Ann Lee", "Nonpartisan", level: "local", county: "Erie", jurisdiction: "Elma")
      ].to_yaml)

      expect { convert }.to raise_error(Seeds::BallotManifestConverter::Error, /Elma is missing from county_equivalents.yml/)
    end
  end

  # Ballots print "Town of Aurora"; the Census-based municipalities list the town as Aurora.
  describe "places a contribution already lists" do
    def contribute_places(*places)
      write("manifests/contributions/census/ny_municipalities.yml", {
        "format" => "micharisma-seeds/v1", "namespace" => "MIC", "catalog" => "ASC",
        "records" => places.map { |code, name| { "type" => "Municipality", "code" => code, "attributes" => { "name" => name } } }
      }.to_yaml)
    end

    def supervisor(jurisdiction)
      write("races/2026/new_york/local/erie.yml", [
        row("Town Supervisor", "", "James J. Bach", "Nonpartisan", level: "local", county: "Erie", jurisdiction: jurisdiction)
      ].to_yaml)
    end

    it "uses the contribution's code and name instead of minting its own" do
      contribute_places([ "MUNICIPALITY-USA-NY-AURORA", "Aurora" ])
      supervisor("Town of Aurora")

      convert

      foundation = root.join("manifests/2026/new_york/foundation.yml").read
      expect(foundation).not_to include("TOWN_OF_AURORA")
      expect(root.join("manifests/2026/new_york/local/erie.yml").read).to include("OFFICE-USA-NY-AURORA-TOWN_SUPERVISOR", "office: OFFICE-USA-NY-AURORA-TOWN_SUPERVISOR")
    end

    it "settles a town and village of one name by the printed type" do
      contribute_places([ "MUNICIPALITY-USA-NY-AURORA_TOWN", "Aurora" ], [ "MUNICIPALITY-USA-NY-AURORA_VILLAGE", "Aurora" ])
      supervisor("Town of Aurora")

      convert

      expect(root.join("manifests/2026/new_york/local/erie.yml").read).to include("OFFICE-USA-NY-AURORA_TOWN-TOWN_SUPERVISOR")
    end

    it "asks place_codes.yml to settle a tie the printed name cannot" do
      contribute_places([ "MUNICIPALITY-USA-NY-AURORA_TOWN", "Aurora" ], [ "MUNICIPALITY-USA-NY-AURORA_VILLAGE", "Aurora" ])
      supervisor("Aurora")

      expect { convert }.to raise_error(Seeds::BallotManifestConverter::Error, /Aurora could be MUNICIPALITY-USA-NY-AURORA_TOWN or MUNICIPALITY-USA-NY-AURORA_VILLAGE; choose one in place_codes.yml/)

      write("conversion/2026/new_york/place_codes.yml", { "Aurora" => "MUNICIPALITY-USA-NY-AURORA_VILLAGE" }.to_yaml)
      convert

      expect(root.join("manifests/2026/new_york/local/erie.yml").read).to include("OFFICE-USA-NY-AURORA_VILLAGE-TOWN_SUPERVISOR")
    end
  end

  it "gives each judge standing for retention a race of their own" do
    retention_note = "appellate judge (Florida appellate judges stand for merit retention, yes/no)"
    write("races/2026/new_york/state/appeal.yml", [
      row("District Court of Appeal", "1", "Joseph Lewis Jr.", "", notes: retention_note),
      row("District Court of Appeal", "1", "Rachel Nordby", "", notes: retention_note)
    ].to_yaml)

    convert

    usernames = YAML.load_file(root.join("conversion/2026/new_york/usernames.yml"))
    lewis, nordby = usernames.values_at("District Court of Appeal|1|Joseph Lewis Jr.", "District Court of Appeal|1|Rachel Nordby")
    expect(lewis).to match(username_like("lewis_js"))
    expect(nordby).to match(username_like("nordby_rc"))
    judicial = root.join("manifests/2026/new_york/judicial.yml").read
    expect(judicial).to include("RACE-USA-NY-APPEAL-DCA_1-APPELLATE_JUDGE-RETENTION_OF_JOSEPH_LEWIS_JR-2026_GENERAL",
                                "RACE-USA-NY-APPEAL-DCA_1-APPELLATE_JUDGE-RETENTION_OF_RACHEL_NORDBY-2026_GENERAL")
  end

  it "gives two citizens with the same printed name the same name code and different disambiguators" do
    write("races/2026/new_york/state/state_senator.yml", [
      row("State Senator", "1", "John Smith", "Republican"),
      row("State Senator", "2", "John Smith", "Republican")
    ].to_yaml)

    convert

    usernames = YAML.load_file(root.join("conversion/2026/new_york/usernames.yml"))
    first, second = usernames.values_at("State Senator|1|John Smith", "State Senator|2|John Smith")
    expect([ first, second ]).to all(match(username_like("smith_jh")))
    expect(first).not_to eq(second)
  end

  it "abbreviates the given name to its first letter and next consonant" do
    write("races/2026/new_york/state/attorney_general.yml", [
      row("Attorney General", "", "Letitia A. James", "Democratic"),
      row("Attorney General", "", "Ann Yee", "Republican")
    ].to_yaml)

    convert

    usernames = YAML.load_file(root.join("conversion/2026/new_york/usernames.yml"))
    expect(usernames.fetch("Attorney General||Letitia A. James")).to match(username_like("james_lt"))
    expect(usernames.fetch("Attorney General||Ann Yee")).to match(username_like("yee_an"))
  end

  # Usernames name no state, so a disambiguator already issued in another state is never reissued.
  it "skips a username another state has already issued" do
    write("conversion/2026/florida/usernames.yml", { "Governor||Kathy Hochul" => "hochul_kt_9a" }.to_yaml)

    convert

    usernames = YAML.load_file(root.join("conversion/2026/new_york/usernames.yml"))
    expect(usernames.fetch("Governor||Kathy Hochul")).to eq("hochul_kt_9b")
  end
end

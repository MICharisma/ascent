require "csv"
require "digest"
require Rails.root.join("db", "seeds", "data_paths").to_s

module Seeds
  # Converts one state's sourced 2026 ballot rows into micharisma-seeds/v1 manifests for the
  # Ascent catalog, and reports the judgments conversion cannot settle on its own.
  #
  # Reads   races/2026/<state>/{federal,state,local}/*.yml, races/2026/<state>/conflicts.csv,
  #         conversion/2026/<state>/{rules.yml,offices.yml}, us_states.yml, and the coded
  #         Positions in manifests/foundation.yml.
  # Writes  manifests/2026/<state>/**/*.yml and
  #         conversion/2026/<state>/{usernames.yml,name_spellings.yml,judgments.md}.
  #
  # Usernames already recorded in usernames.yml are reused, so a username never changes once issued,
  # and a new one is checked against every state's usernames.yml.
  class BallotManifestConverter
    class Error < StandardError; end

    YEAR = 2026
    # Chamber token, seat prefix, manifest file, and whether one office fills the whole district.
    DISTRICT_KINDS = {
      "Congressional District" => [ "CONGRESS", "CD", "congress", true ],
      "State Senate District" => [ "SENATE", "SD", "state_senate", true ],
      "Assembly District" => [ "ASSEMBLY", "AD", "assembly", true ],
      "State House District" => [ "HOUSE", "HD", "state_house", true ],
      "House of Delegates District" => [ "HOUSE", "HD", "state_house", true ],
      "Governor's Council District" => [ "GOVERNORS_COUNCIL", "GC", "governors_council", true ],
      "Judicial District" => [ "JUDICIAL", "JD", "judicial", false ],
      "District Court of Appeal" => [ "APPEAL", "DCA", "judicial", false ],
      "Judicial Circuit" => [ "CIRCUIT", "CIR", "judicial", false ]
    }.freeze
    PILOT_STATEWIDE_OFFICES = [ "Governor", "Lt. Governor", "Lieutenant Governor", "Comptroller", "Attorney General" ].freeze
    PILOT_DISTRICT_OFFICES = [ "Representative in Congress", "State Senator", "Member of Assembly" ].freeze
    PILOT_CONTESTS_PER_OFFICE = 4
    CERTIFICATION_STATUSES = [ [ /tentative|subject to change/i, "tentative" ], [ /unofficial/i, "unofficial" ], [ /certified/i, "certified" ] ].freeze
    UNMAPPED_FIELDS = %w[incumbent fec_candidate_id county jurisdiction notes cross_check_url].freeze
    LOCAL_OFFICE_KEYS = %w[position seat part body town term].freeze
    TOWN_PREFIX = /\A(?:Town|City|Village) of /i

    attr_reader :summary

    # Disambiguators skip look-alike characters: 0 and 1, I and O.
    DISAMBIGUATOR_DIGITS = ("2".."9").to_a.freeze
    DISAMBIGUATOR_LETTERS = (("A".."Z").to_a - %w[I O]).map(&:downcase).freeze
    DISAMBIGUATORS = DISAMBIGUATOR_DIGITS.product(DISAMBIGUATOR_LETTERS).map(&:join).freeze

    def self.first_appearance_facts(state:, election_date:, printed_name:, printed_office:)
      state_code = state.to_s.strip.upcase.delete_prefix("STATE-USA-")
      [ state_code, election_date, printed_name, printed_office ].map { it.to_s.squish }.join(" | ")
    end

    def self.mint_username(base:, state:, election_date:, printed_name:, printed_office:, taken: Set.new)
      facts = first_appearance_facts(state: state, election_date: election_date, printed_name: printed_name, printed_office: printed_office)
      start = Digest::SHA256.hexdigest(facts).to_i(16) % DISAMBIGUATORS.size
      DISAMBIGUATORS.size.times do |offset|
        candidate = "#{base}_#{DISAMBIGUATORS[(start + offset) % DISAMBIGUATORS.size]}"
        return candidate unless taken.include?(candidate)
      end
      raise Error, "All #{DISAMBIGUATORS.size} disambiguators are taken for CITIZEN-#{base.upcase}"
    end

    def initialize(state_dir:, selection: :pilot, root: SeedDataPaths.primary_root)
      @state_dir, @selection, @root = state_dir, selection, Pathname.new(root)
    end

    def call
      load_inputs
      contests = selected_contests
      races = contests.map { |key, rows| placement(key, rows) }.group_by { |placed| placed[:race_code] }.map do |race_code, placed|
        refuse_merged_contests(race_code, placed)
        race_manifest(placed)
      end

      write_manifests(races)
      write_reports(contests)
      @summary = {
        contests: races.size,
        candidacies: races.sum { |race| race[:candidacies] },
        off_ballot: @off_ballot.size,
        usernames_issued: @issued.size,
        files: @written_paths.size
      }
    end

    private

    def load_inputs
      curated = @root.join("manifests/contributions/ascent-identity/citizens.yml")
      @curated_citizen_codes = curated.file? ? MICharismaSeeders::Reader.new.read(curated.to_s).flat_map { [ it.code, *it.aliases ] }.to_set : Set.new
      paths = Dir.glob(@root.join("races", YEAR.to_s, @state_dir, "{federal,state,local}", "*.yml").to_s).sort
      raise Error, "No ballot rows for #{@state_dir}" if paths.empty?

      @rows = paths.flat_map { |path| BallotRows.rows_from(path) }
      @state_code = @rows.first.fetch("state")
      @state_name = YAML.load_file(@root.join("us_states.yml")).fetch("states").find { |state| state.fetch("code") == @state_code }.fetch("name")
      @state_path = "USA-#{@state_code}"
      conflicts_path = @root.join("races", YEAR.to_s, @state_dir, "conflicts.csv")
      @conflicts = conflicts_path.exist? ? CSV.read(conflicts_path, headers: true).map(&:to_h) : []
      load_rules(YAML.load_file(conversion_dir.join("rules.yml")))
      @usernames = (path = conversion_dir.join("usernames.yml")).exist? ? YAML.load_file(path) : {}
      @county_equivalents = (path = conversion_dir.join("county_equivalents.yml")).exist? ? load_county_equivalents(YAML.load_file(path)) : nil
      @place_codes = (path = conversion_dir.join("place_codes.yml")).exist? ? YAML.load_file(path) : {}
      # Manifests name the catalog's Positions by code and never define their own.
      @positions = YAML.load_file(foundation_path).fetch("records").select { |record| record["type"] == "Position" }
                       .to_h { |record| [ record["code"], record.dig("attributes", "title") ] }
      @local_offices = load_local_offices((path = conversion_dir.join("offices.yml")).exist? ? YAML.load_file(path) : {})
      @places = {}
      @issued = {}
      @off_ballot = []
      @unplaced_conflicts = []
      @label_tally = Hash.new { |hash, key| hash[key] = Set.new }
      @certifications = Hash.new { |hash, key| hash[key] = Set.new }
      @specials = Set.new
      @split_counties = Set.new
      @written_paths = []
    end

    def load_rules(rules)
      @parties = rules.fetch("parties")
      @party_by_label = @parties.flat_map { |party| party.fetch("labels").map { |label| [ label, party ] } }.to_h
      @label_kinds = BallotRows::LABEL_KINDS.merge(rules.fetch("label_kinds", {}))
      @other_label_kind = rules.fetch("other_labels", "unclassified")
      @unprinted_labels = rules.fetch("unprinted_labels", [])
      @unprinted_levels = rules.fetch("unprinted_levels", [])
      @special_patterns = rules.fetch("special_elections", []).map { |pattern| Regexp.new(pattern, Regexp::IGNORECASE) }
    end

    # A state whose towns belong to county-equivalents, like Connecticut's planning regions, lists them;
    # its towns then take their county from that list instead of the county a ballot row prints.
    def load_county_equivalents(listing)
      listing.fetch("counties").each_with_object({}) do |county, towns|
        place = { code: county.fetch("code"), name: county.fetch("name") }
        place[:path] = "#{@state_path}-COUNTY_#{place[:code].delete_prefix("COUNTY-#{@state_path}-")}"
        place[:file] = place[:code].delete_prefix("COUNTY-#{@state_path}-").downcase
        county.fetch("towns").each { |town| towns[town] = place }
      end
    end

    # A bare code names the Position; a mapping also carries the seat, special district, town, or term the title prints.
    def load_local_offices(listing)
      listing.to_h do |title, entry|
        entry = { "position" => entry } if entry.is_a?(String)
        unknown = entry.keys - LOCAL_OFFICE_KEYS
        raise Error, "offices.yml gives #{title.inspect} unknown keys: #{unknown.join(", ")}" if unknown.any?

        position(entry.fetch("position"))
        [ title, entry ]
      end
    end

    def local_office(title)
      @local_offices.fetch(title) { raise Error, "#{title.inspect} is missing from #{conversion_dir.join("offices.yml")}" }
    end

    def position(code)
      raise Error, "#{code} is not a Position in #{foundation_path}" unless @positions.key?(code)

      code
    end

    def conversion_dir
      @root.join("conversion", YEAR.to_s, @state_dir)
    end

    def manifest_dir
      @root.join("manifests", YEAR.to_s, @state_dir)
    end

    def foundation_path
      @root.join("manifests", "foundation.yml")
    end

    def local?(row)
      row.fetch("office_level") == "local"
    end

    def retention?(row)
      row.fetch("notes", "").to_s.include?("merit retention")
    end

    # Local contests are told apart by the places their rows name; a retention vote is one judge's own contest.
    def contest_key(row)
      key = [ row.fetch("office"), row.fetch("district") ]
      return key + [ row["county"].to_s, row["jurisdiction"].to_s ] if local?(row)
      return key + [ "retention: #{row.fetch("candidate_name")}" ] if retention?(row)

      key
    end

    # The pilot covers statewide contests, the most contested districts for each legislative and
    # congressional office, and every contest in those offices with a logged source conflict.
    def selected_contests
      contests = @rows.group_by { |row| contest_key(row) }
      return contests if @selection == :all

      conflicted = @conflicts.map { |conflict| [ conflict["office"], conflict["district"].to_s ] }
      chosen = contests.keys.select { |key| key.size == 2 && key.last.empty? && PILOT_STATEWIDE_OFFICES.include?(key.first) }
      PILOT_DISTRICT_OFFICES.each do |office|
        ranked = contests.select { |key, _| key.size == 2 && key.first == office }
                         .sort_by { |(_, district), rows| [ -rows.map { |row| row["candidate_name"] }.uniq.size, -rows.size, district.to_i ] }
        chosen += ranked.first(PILOT_CONTESTS_PER_OFFICE).map(&:first)
        chosen += ranked.map(&:first).select { |key| conflicted.include?(key) }
      end
      contests.slice(*chosen.uniq)
    end

    def placement(key, rows)
      placed = local?(rows.first) ? local_placement(rows) : state_level_placement(rows)
      contest = "#{YEAR}_#{special?(rows) ? "SPECIAL" : "GENERAL"}"
      @specials << key if special?(rows)
      # A race for part of a term, like an unexpired term, is its own race for the same office.
      race_path = [ placed[:office_path], (token(placed[:term]) if placed[:term]) ].compact.join("-")
      placed.merge(
        key: key, rows: rows, contest: contest, race_path: race_path,
        election_code: "ELECTION-#{placed[:place][:path]}-#{contest}",
        race_code: "RACE-#{race_path}-#{contest}"
      )
    end

    # Contests printed differently share a race only by mistake, such as a vacancy mapped without its term.
    def refuse_merged_contests(race_code, placed)
      printed = placed.map { |contest| contest[:key].first(2) }.uniq
      return if printed.one?

      raise Error, "#{printed.map { it.compact_blank.join(" ") }.join(" and ")} would share #{race_code}; give each its own seat or term in offices.yml"
    end

    def state_level_placement(rows)
      row = rows.first
      position_code, district_kind = BallotRows::STATE_LEVEL_OFFICES.fetch(row.fetch("office")) do
        raise Error, "No position mapping for #{@state_code} office #{row.fetch("office").inspect}"
      end
      position_token = position(position_code).delete_prefix("POSITION-")
      retention = "Retention of #{row.fetch("candidate_name")}" if retention?(row)
      district = row.fetch("district")
      if district.empty?
        return {
          position_code: position_code, place: state_place,
          office_path: [ "#{@state_path}-#{position_token}", (token(retention) if retention) ].compact.join("-"),
          seat_code: (token(retention) if retention),
          file: "statewide"
        }
      end

      chamber, prefix, file, single_seat = DISTRICT_KINDS.fetch(district_kind) { raise Error, "No district tokens for #{district_kind}" }
      number, group = district.match(/\ACircuit (\d+)(?:, (.+))?\z/)&.captures || [ district, nil ]
      numeric = number.match?(/\A\d+\z/)
      district_token = numeric ? "#{prefix}_#{number}" : token(number)
      place = district_place("#{@state_path}-#{chamber}-#{district_token}", "#{@state_name} #{district_kind}#{numeric ? " " : ": "}#{number}", district_kind)
      seat = retention || group
      if single_seat && seat.nil?
        office_path, seat_code = place[:path], district_token
      else
        office_path = [ place[:path], position_token, (token(seat) if seat) ].compact.join("-")
        seat_code = [ district_token, (token(seat) if seat) ].compact.join("_")
      end
      { position_code: position_code, place: place, office_path: office_path, seat_code: seat_code, file: file }
    end

    # Local offices fill the Position offices.yml maps their printed title to, and belong to the most
    # specific single place the source names. Contests spanning several places, or naming none, get a
    # District named for the Position and what it covers.
    def local_placement(rows)
      row = rows.first
      office = local_office(row.fetch("office"))
      title = @positions.fetch(office["position"])
      localities = BallotRows.places(office["town"] || row["jurisdiction"])
      towns = localities.reject { |place| BallotRows.county_name?(place) }
      district = row.fetch("district").presence
      if district && names_place?(district, localities + BallotRows.places(row["county"]))
        district = nil
      elsif district&.match?(TOWN_PREFIX) && towns.empty?
        towns, district = [ district ], nil
      end
      counties = local_counties(row, localities, towns)
      seat = [ office["body"], office["seat"] || district, office["part"] ].compact.join(" ").presence
      office_district = towns.many? || (towns.empty? && !counties.one?)

      place = if towns.one?
                municipality_place(BallotRows.title_case(towns.first), (county_place(counties.first) if counties.one?))
      elsif towns.empty? && counties.one?
                county_place(counties.first)
      elsif towns.empty? && counties.empty?
                covered, seat = seat, nil
                district_place("#{@state_path}-#{token(title)}-#{token(covered)}", "#{@state_name} #{title}: #{covered}", "#{title} district")
      else
                covered = towns.any? ? towns.map { |name| BallotRows.title_case(name) } : counties.map { it[:name] }
                district_place("#{@state_path}-#{token(title)}-#{token(covered.join(" "))}", "#{@state_name} #{title} (#{covered.join(", ")})", "#{title} district")
      end
      # A district drawn for this office already carries its title.
      office_path = [ place[:path], (token(title) unless office_district), (token(seat) if seat) ].compact.join("-")
      {
        position_code: office["position"], place: place, office_path: office_path,
        seat_code: (token(seat) if seat), term: office["term"],
        file: "local/#{counties.one? ? counties.first[:file] : "multi_county"}"
      }
    end

    # A district column that prints the office's own town or county names its place, not a seat.
    def names_place?(district, places)
      places.any? do |place|
        loose_place_name(district) == loose_place_name(place) ||
          (BallotRows.county_name?(district) && BallotRows.county_name(district) == BallotRows.county_name(place))
      end
    end

    def state_place
      { code: "STATE-#{@state_path}", path: @state_path, name: @state_name }
    end

    def district_place(path, name, kind)
      add_place("DISTRICT-#{path}", record("District", "DISTRICT-#{path}", { "name" => name, "kind" => kind.downcase }))
      { code: "DISTRICT-#{path}", path: path, name: name }
    end

    # The counties a local contest's rows name, or its towns' county-equivalents where the state lists them.
    def local_counties(row, localities, towns)
      if @county_equivalents
        return towns.map do |town|
          @county_equivalents.fetch(BallotRows.title_case(town)) { raise Error, "#{town} is missing from county_equivalents.yml" }
        end.uniq
      end

      (BallotRows.places(row["county"]) + (localities - towns)).uniq { |place| BallotRows.county_name(place) }.map { printed_county(it) }
    end

    def printed_county(printed_name)
      name = BallotRows.county_name(printed_name)
      county_token = token(name.delete_suffix(" County"))
      { code: "COUNTY-#{@state_path}-#{county_token}", path: "#{@state_path}-COUNTY_#{county_token}", name: name, file: slug(name.delete_suffix(" County")) }
    end

    def county_place(county)
      add_place(county[:code], record("County", county[:code], { "name" => county[:name] }))
      county.slice(:code, :path, :name)
    end

    def municipality_place(name, county)
      if (canonical = canonical_place(name, county))
        return { code: canonical[:code], path: canonical[:code].delete_prefix("MUNICIPALITY-"), name: canonical[:name] }
      end

      code = "MUNICIPALITY-#{@state_path}-#{token(name)}"
      definition = record("Municipality", code, { "name" => name }, county ? { "county" => county[:code] } : {})
      if (existing = @places[code]) && existing["references"] != definition["references"]
        # A town listed under different counties is recorded without one.
        @split_counties << name
        existing.delete("references")
      else
        add_place(code, definition)
      end
      { code: code, path: "#{@state_path}-#{token(name)}", name: name }
    end

    # A town that a contribution already lists, such as the Census-based municipalities, keeps that
    # contribution's code and name: ballots print "Town of Bolton" or "Bristol City" for the places
    # listed as Bolton and Bristol. A tie the printed type and county can't settle is decided in
    # the state's place_codes.yml.
    def canonical_place(printed_name, county)
      if (code = @place_codes[printed_name])
        return canonical_places.values.flatten.find { it[:code] == code } || raise(Error, "place_codes.yml maps #{printed_name} to unknown #{code}")
      end

      candidates = canonical_places.fetch(loose_place_name(printed_name), [])
      same_code = candidates.find { it[:code] == "MUNICIPALITY-#{@state_path}-#{token(printed_name)}" }
      return same_code if same_code

      type = printed_name[/\A(Town|City|Village|Borough) of /, 1] || printed_name[/ (City|Town)\z/, 1]
      candidates = narrow(candidates) { it[:code].match?(/_#{type.upcase}(_|\z)/) } if type
      candidates = narrow(candidates) { it[:county] == county[:code] } if county
      # A lone place of the same name in another county is a different place.
      return if candidates.one? && county && candidates.first[:county] && candidates.first[:county] != county[:code]
      return candidates.first if candidates.size <= 1

      raise Error, "#{printed_name} could be #{candidates.map { it[:code] }.sort.join(" or ")}; choose one in place_codes.yml"
    end

    def narrow(candidates)
      return candidates if candidates.size <= 1

      chosen = candidates.select { yield it }
      chosen.empty? ? candidates : chosen
    end

    def loose_place_name(name)
      slug(name.sub(/\A(Town|City|Village|Borough) of /, "").sub(/ (City|Town|Village|Borough)\z/, "")).delete("_")
    end

    def canonical_places
      @canonical_places ||= Dir.glob(@root.join("manifests", "contributions", "**", "*.{yml,yaml}").to_s).flat_map do |path|
        next [] unless File.read(path).include?("code: MUNICIPALITY-#{@state_path}-")

        document = YAML.load_file(path)
        (document["records"].to_a + document["groups"].to_a.flat_map { it["records"].to_a }).select do |entry|
          entry["type"] == "Municipality" && entry["code"].start_with?("MUNICIPALITY-#{@state_path}-")
        end
      end.map do |entry|
        { code: entry["code"], name: entry.dig("attributes", "name"), county: entry.dig("references", "county") }
      end.uniq { it[:code] }.group_by { loose_place_name(it[:name]) }
    end

    def add_place(code, definition)
      @places[code] ||= definition
    end

    def race_manifest(placed)
      first = placed.first
      rows = placed.flat_map { |contest| contest[:rows] }
      office_code = "OFFICE-#{first[:office_path]}"
      records = [
        record("Office", office_code, { "seat_code" => first[:seat_code], "is_active" => true }.compact,
               "position" => first[:position_code], "jurisdiction" => first[:place][:code]),
        record("Race", first[:race_code], { "status" => "upcoming", "certification_status" => certification(rows), "description" => BallotRows.race_description(rows) }.compact,
               "election" => first[:election_code], "office" => office_code)
      ]
      candidates = placed.flat_map { |contest| contest[:rows].map { |row| [ row.fetch("candidate_name"), contest, row ] } }.group_by(&:first)
      candidacies = candidates.map do |name, entries|
        candidate_records(name, entries.map(&:last), registry_key(entries.first[1][:key], name), first, "active")
      end
      placed.select { |contest| contest[:key].size == 2 }.each do |contest|
        off_ballot_names(contest).each do |name|
          candidacies << candidate_records(name, [], registry_key(contest[:key], name), first, "off_ballot")
        end
      end

      { file: first[:file], election: election_record(first, rows), records: records + candidacies.flatten, candidacies: candidacies.size }
    end

    def registry_key(contest_key, name)
      (contest_key.first(2) + (contest_key.size == 4 ? contest_key.last(2) : []) + [ name ]).join("|")
    end

    def candidate_records(name, rows, key, placed, participation)
      parts = BallotRows.name_parts(name)
      username = username_for(key, parts, placed, name)
      citizen = record("Citizen", "CITIZEN-#{username.upcase}",
                      { "username" => username, "username_status" => "provisional" }.merge(parts.transform_keys(&:to_s).compact))
      lines = rows.filter_map { |row| ballot_line(row) }.uniq { |line| line["label"] }
      attributes = { "status" => "active", "participation" => participation }
      attributes["ballot_lines"] = lines if lines.any?
      candidacy = record("Candidacy", "CANDIDACY-#{placed[:race_path]}-#{placed[:contest]}-#{username.upcase}", attributes,
                         "race" => placed[:race_code], "citizen" => citizen["code"])
      @curated_citizen_codes.include?(citizen["code"]) ? [ candidacy ] : [ citizen, candidacy ]
    end

    def ballot_line(row)
      label = row.fetch("party")
      return if label.blank?

      if @unprinted_levels.include?(row.fetch("office_level")) || @unprinted_labels.include?(label)
        @label_tally["not printed"] << label
        return
      end
      if (party = @party_by_label[label])
        @label_tally["party"] << label
        { "label" => label, "kind" => "party", "party" => "PARTY-#{@state_path}-#{party.fetch("code")}" }
      else
        kind = @label_kinds.fetch(label, @other_label_kind)
        @label_tally[kind] << label
        { "label" => label, "kind" => kind }
      end
    end

    # Sources disagreeing on whether a citizen belongs in the contest: include them, off the ballot.
    def off_ballot_names(contest)
      office, district = contest[:key]
      printed = contest[:rows].map { |row| row["candidate_name"] }
      @conflicts.select { |conflict| conflict["field"] == "presence" && conflict["office"] == office && conflict["district"].to_s == district && absent_from_official_source?(conflict) }
                .reject { |conflict| printed.include?(conflict["candidate_name"]) }
                .each { |conflict| @off_ballot << conflict }
                .map { |conflict| conflict["candidate_name"] }
                .uniq
    end

    # Sources word this differently: "not listed", "(not on SoS list)", "(no DOS line)".
    def absent_from_official_source?(conflict)
      conflict["value_a"].to_s.match?(/\A\(?(?:not|no)\b/i)
    end

    def election_record(placed, rows)
      special = placed[:contest].end_with?("SPECIAL")
      record("Election", placed[:election_code],
             { "name" => "#{placed[:place][:name]} #{special ? "Special" : "General"} Election #{YEAR}", "kind" => special ? "special" : "general",
               "election_date" => rows.first.fetch("election_date"), "status" => "upcoming", "is_mock" => false, "is_historical" => false },
             "jurisdiction" => placed[:place][:code], "year" => "YEAR-#{YEAR}")
    end

    def special?(rows)
      rows.any? { |row| @special_patterns.any? { |pattern| row.fetch("office").match?(pattern) || row.fetch("notes", "").to_s.match?(pattern) } }
    end

    def certification(rows)
      statuses = rows.map { |row| row.fetch("status") }.uniq
      mapped = statuses.map { |status| CERTIFICATION_STATUSES.find { |pattern, _| status.match?(pattern) }&.last }
      statuses.zip(mapped).each { |status, value| @certifications[status] << value }
      mapped.uniq.one? ? mapped.first : nil
    end

    def username_for(key, parts, placed, name)
      return @usernames.fetch(key) if @usernames.key?(key)

      username = self.class.mint_username(
        base: name_code(parts),
        state: @state_code,
        election_date: placed[:rows].first.fetch("election_date"),
        printed_name: name,
        printed_office: placed[:key].first(2).compact_blank.join(" "),
        taken: taken_usernames
      )
      taken_usernames << username
      @issued[key] = @usernames[key] = username
    end

    # The surname, then the given name's first letter and its next consonant: Letitia James is james_lt.
    def name_code(parts)
      surname_words = parts[:last_name].delete(",").split
      surname_words.pop if surname_words.size > 1 && surname_words.last.match?(BallotRows::NAME_SUFFIX)
      [ slug(surname_words.last), given_letters(parts[:first_name]) ].compact_blank.join("_")
    end

    def given_letters(first_name)
      letters = slug(first_name).delete("_")
      return if letters.empty?

      letters[0] + (letters[1..][/[^aeiou0-9]/] || letters[1].to_s)
    end

    # Every username issued in any state, and any a contribution already uses, so no two citizens share one.
    def taken_usernames
      @taken_usernames ||= begin
        issued = Dir.glob(@root.join("conversion", "*", "*", "usernames.yml").to_s).flat_map { |path| YAML.load_file(path).values }
        contributed = Dir.glob(@root.join("manifests", "contributions", "**", "*.{yml,yaml,json}").to_s).flat_map do |path|
          File.read(path).scan(/(?:code|"[Cc]ode")\s*:\s*"?CITIZEN-([A-Z0-9_]+)/).flatten.map(&:downcase)
        end
        (issued + contributed + @usernames.values).to_set
      end
    end

    def slug(text)
      ActiveSupport::Inflector.transliterate(text.to_s).downcase.delete("'").gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    end

    def token(text)
      slug(text).upcase
    end

    def record(type, code, attributes = {}, references = {})
      { "type" => type, "code" => code, "attributes" => attributes, "references" => references }.reject { |_, value| value.respond_to?(:empty?) && value.empty? }
    end

    def write_manifests(races)
      FileUtils.rm_rf(manifest_dir)
      parties = @parties.map { |party| record("Party", "PARTY-#{@state_path}-#{party.fetch("code")}", { "name" => party.fetch("name") }) }
      places = @places.values.sort_by { |place| [ %w[County Municipality District].index(place["type"]), place["code"] ] }
      write_manifest(manifest_dir.join("foundation.yml"), "#{@state_name}: the state, its parties, and the places its contests belong to.",
                     "records" => [ record("State", "STATE-#{@state_path}", { "code" => @state_code, "name" => @state_name }, "country" => "COUNTRY-USA") ],
                     "groups" => [ { "scope" => { "state" => "STATE-#{@state_path}" }, "records" => parties + places } ])
      races.group_by { |race| race[:file] }.sort.each do |file, file_races|
        elections = file_races.map { |race| race[:election] }.uniq { |election| election["code"] }
        write_manifest(manifest_dir.join("#{file}.yml"), "#{@state_name} #{file.delete_prefix("local/").tr("_", " ")} contests on the #{YEAR} general election ballot.",
                       "scope" => { "state" => "STATE-#{@state_path}" },
                       "records" => elections,
                       "groups" => file_races.map { |race| { "records" => race[:records] } })
      end
    end

    def write_manifest(path, description, body)
      document = { "format" => "micharisma-seeds/v1", "namespace" => "MIC", "catalog" => "ASC" }.merge(body)
      write(path, "# #{description}\n# Generated by Seeds::BallotManifestConverter from the sourced ballot rows; edit the inputs, not this file.\n" +
                  document.to_yaml(line_width: -1).delete_prefix("---\n"))
    end

    def write(path, contents)
      FileUtils.mkdir_p(path.dirname)
      path.write(contents)
      @written_paths << path
    end

    def write_reports(contests)
      write(conversion_dir.join("usernames.yml"),
            "# Issued provisional usernames, keyed by contest and printed name. Reused on every conversion; do not edit an issued username.\n" +
            @usernames.sort.to_h.to_yaml(line_width: -1).delete_prefix("---\n"))
      write(conversion_dir.join("name_spellings.yml"),
            "# Other spellings of a citizen's name found in cross-check sources. The ballot spelling is kept on the Citizen.\n" +
            name_spellings(contests).to_yaml(line_width: -1).delete_prefix("---\n"))
      write(conversion_dir.join("judgments.md"), judgments(contests))
    end

    # A conflict names an office and district; it belongs to the converted contest whose rows include its citizen.
    def conflict_contest(conflict, contests)
      matches = contests.select do |(office, district), rows|
        office == conflict["office"] && district == conflict["district"].to_s && rows.any? { |row| row["candidate_name"] == conflict["candidate_name"] }
      end
      matches.size == 1 ? matches.keys.first : nil
    end

    def name_spellings(contests)
      @conflicts.select { |conflict| conflict["field"] == "candidate_name" }.filter_map do |conflict|
        key = conflict_contest(conflict, contests)
        next unless key

        {
          "username" => @usernames[registry_key(key, conflict["candidate_name"])],
          "ballot_spelling" => conflict["value_a"],
          "other_spelling" => conflict["value_b"],
          "other_source" => conflict["source_b"],
          "note" => conflict["note"]
        }
      end
    end

    def judgments(contests)
      in_selection = ->(conflict) { conflict_contest(conflict, contests) }
      lines = [ "# #{@state_name} #{YEAR} conversion judgments", "",
                "Generated by `Seeds::BallotManifestConverter` (selection: #{@selection}). Each item below is a decision the conversion made or left open; review them before relying on the manifests.", "" ]
      lines += [ "## Contests converted", "" ]
      if @selection == :pilot
        lines << "Selection rule: every statewide contest among #{PILOT_STATEWIDE_OFFICES.uniq.join(", ")}; for each of #{PILOT_DISTRICT_OFFICES.join(", ")}, the #{PILOT_CONTESTS_PER_OFFICE} districts with the most distinct candidates (then the most printed lines, then the lowest district number); plus every contest in those offices with a logged source conflict."
        lines << ""
      end
      lines << "#{contests.size} source contests from #{contests.values.sum(&:size)} rows: #{contests.keys.count { |key| key.size == 4 }} local, #{contests.keys.count { |key| key.size != 4 }} federal and state."
      if @specials.any?
        lines += [ "", "Special elections (matched by `rules.yml`): #{@specials.map { |key| key.first(2).compact_blank.join(" ") }.uniq.sort.join("; ")}." ]
      end
      lines += [ "", "## Ballot line labels", "", "Rules come from `rules.yml`. Party lines link to Party records and count as the party's endorsement." ]
      @label_tally.sort.each { |kind, labels| lines << "- #{kind}: #{labels.sort.join(", ")}" }
      lines += [ "", "## Citizens included off the ballot", "" ]
      lines += @off_ballot.any? ? @off_ballot.map { |conflict| "- #{conflict["candidate_name"]} (#{contest_label(conflict)}): #{conflict["note"]}. Included with participation `off_ballot` and no ballot line." } : [ "None." ]
      lines += [ "", "## Name spellings", "", "#{name_spellings(contests).size} other spellings are recorded in `name_spellings.yml`. Each Citizen keeps the official ballot spelling." ]
      applied = %w[candidate_name]
      placed = @conflicts.select { |conflict| conflict["field"] == "presence" ? @off_ballot.include?(conflict) : applied.include?(conflict["field"]) && in_selection.call(conflict) }
      remaining = @conflicts - placed
      lines += [ "", "## Conflicts not applied", "" ]
      lines += remaining.any? ? remaining.map { |conflict| "- #{conflict["candidate_name"]} (#{contest_label(conflict)}), #{conflict["field"]}: kept `#{conflict["value_a"]}`; other source has `#{conflict["value_b"]}`. #{conflict["note"]}" } : [ "None." ]
      lines += [ "", "## Certification status", "" ]
      @certifications.sort.each { |status, values| lines << "- `#{status.presence || "(blank)"}` → #{values.map { |value| value ? "`#{value}`" : "not a certification status (left blank)" }.join(", ")}" }
      if @split_counties.any?
        lines += [ "", "## Towns listed under different counties", "", "Recorded without a county: #{@split_counties.sort.join(", ")}." ]
      end
      lines += [ "", "## Fields not stored", "", "The manifests do not store #{UNMAPPED_FIELDS.map { |field| "`#{field}`" }.join(", ")}. They remain in the source rows under `races/#{YEAR}/#{@state_dir}/`." ]
      surname_only = contests.values.flatten.map { |row| row["candidate_name"] }.uniq.select { |name| name.split.one? }
      lines += [ "", "## Missing evidence", "", surname_only.any? ? "Printed with a surname only: #{surname_only.join(", ")}." : "No citizen is printed with a surname only." ]
      lines.join("\n") + "\n"
    end

    def contest_label(conflict)
      conflict["district"].to_s.empty? ? conflict["office"] : "#{conflict["office"]} #{conflict["district"]}"
    end
  end
end

module Seeds
  # Reads the sourced ballot rows in the seed-data repository and interprets their printed text:
  # names, office titles, and the places a local contest names.
  module BallotRows
    DATA_GLOB = [ "races", "2026", "*", "{federal,state,local}", "*.yml" ].freeze
    REQUIRED_KEYS = %w[
      election_date
      state
      office
      district
      office_level
      candidate_name
      party
      incumbent
      status
      source_url
      retrieved_on
    ].freeze

    # Federal and state office titles are printed differently in each state.
    # Each maps to a Position's code in manifests/foundation.yml and, for numbered seats, the kind of District that elects it.
    STATE_LEVEL_OFFICES = {
      "Representative in Congress" => [ "POSITION-REPRESENTATIVE", "Congressional District" ],
      "Member, House of Representatives" => [ "POSITION-REPRESENTATIVE", "Congressional District" ],
      "United States Representative" => [ "POSITION-REPRESENTATIVE", "Congressional District" ],
      "Senator in Congress" => [ "POSITION-SENATOR" ],
      "Member, United States Senate" => [ "POSITION-SENATOR" ],
      "United States Senator" => [ "POSITION-SENATOR" ],
      "Governor" => [ "POSITION-GOVERNOR" ],
      "Lt. Governor" => [ "POSITION-LIEUTENANT_GOVERNOR" ],
      "Lieutenant Governor" => [ "POSITION-LIEUTENANT_GOVERNOR" ],
      "Attorney General" => [ "POSITION-ATTORNEY_GENERAL" ],
      "Secretary of State" => [ "POSITION-SECRETARY_OF_STATE" ],
      "Secretary of the State" => [ "POSITION-SECRETARY_OF_STATE" ],
      "Treasurer" => [ "POSITION-TREASURER" ],
      "Comptroller" => [ "POSITION-COMPTROLLER" ],
      "Auditor" => [ "POSITION-AUDITOR" ],
      "Chief Financial Officer" => [ "POSITION-CHIEF_FINANCIAL_OFFICER" ],
      "Commissioner of Agriculture" => [ "POSITION-COMMISSIONER_OF_AGRICULTURE" ],
      "Councillor" => [ "POSITION-GOVERNORS_COUNCILLOR", "Governor's Council District" ],
      "State Senator" => [ "POSITION-STATE_SENATOR", "State Senate District" ],
      "Senator in General Court" => [ "POSITION-STATE_SENATOR", "State Senate District" ],
      "Member of Assembly" => [ "POSITION-STATE_REPRESENTATIVE", "Assembly District" ],
      "State Representative" => [ "POSITION-STATE_REPRESENTATIVE", "State House District" ],
      "Representative in General Court" => [ "POSITION-STATE_REPRESENTATIVE", "State House District" ],
      "Member, House of Delegates" => [ "POSITION-STATE_REPRESENTATIVE", "House of Delegates District" ],
      "Supreme Court Justice" => [ "POSITION-JUSTICE", "Judicial District" ],
      "District Court of Appeal" => [ "POSITION-APPELLATE_JUDGE", "District Court of Appeal" ],
      "Circuit Judge" => [ "POSITION-CIRCUIT_JUDGE", "Judicial Circuit" ],
      "State Attorney" => [ "POSITION-STATE_ATTORNEY", "Judicial Circuit" ],
      "Public Defender" => [ "POSITION-PUBLIC_DEFENDER", "Judicial Circuit" ]
    }.freeze

    # Labels with the same meaning in every state.
    LABEL_KINDS = { "Write-In" => "write_in", "Petitioning Candidate" => "petition" }.freeze
    NAME_SUFFIX = /\A(?:jr|sr|ii|iii|iv|v|esq|esquire)\.?\z/i
    SMALL_WORDS = %w[of and the on in at].freeze

    module_function

    def paths(root)
      Dir.glob(Pathname.new(root).join(*DATA_GLOB).to_s).sort
    end

    def rows_from(path)
      rows = YAML.load_file(path)
      raise "#{path} must contain a list of ballot lines" unless rows.is_a?(Array)

      rows.each do |row|
        missing = REQUIRED_KEYS.reject { |key| row.key?(key) }
        raise "#{path} is missing #{missing.join(", ")}" if missing.any?
      end

      rows
    end

    # The printed name, split so that Citizen#full_name reproduces it.
    def name_parts(printed_name)
      words = printed_name.split
      suffix = words.pop if words.size > 2 && words.last.match?(NAME_SUFFIX)
      last_name = [ words.pop, suffix ].compact.join(" ")

      { first_name: words.shift, middle_name: words.join(" ").presence, last_name: last_name }
    end

    def race_description(rows)
      [
        labelled("Vote for", rows.map { |row| row["vote_for"] }),
        labelled("Source status", rows.map { |row| row.fetch("status") }),
        labelled("Retrieved", rows.map { |row| row.fetch("retrieved_on") }),
        labelled("Sources", rows.map { |row| row.fetch("source_url") })
      ].compact.join(" ")
    end

    def labelled(label, values)
      values = values.compact_blank.uniq
      "#{label}: #{values.join("; ")}." if values.any?
    end

    # A bare "County" names no place; the row's county field says which.
    def places(text)
      text.to_s.split(";").map(&:strip).compact_blank.reject { |place| place.casecmp?("County") }
    end

    def county_name?(place)
      place.match?(/county\z/i)
    end

    # "Erie", "ACCOMACK COUNTY", and "Kings (NYC)" become "Erie County", "Accomack County", and "Kings County".
    def county_name(printed_name)
      name = title_case(printed_name.delete_suffix(" (NYC)"))
      name.match?(/county\z/i) ? name : "#{name} County"
    end

    # Some sources print place names in capitals ("TOWN OF CICERO").
    def title_case(text)
      return text unless text == text.upcase

      text.downcase.split.each_with_index.map do |word, index|
        index.positive? && SMALL_WORDS.include?(word) ? word : word.split("-").map(&:capitalize).join("-")
      end.join(" ")
    end
  end
end

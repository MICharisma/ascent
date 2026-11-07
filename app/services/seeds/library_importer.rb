require Rails.root.join("lib/micharisma_seeders/lib/micharisma_seeders").to_s

module Seeds
  # Imports micharisma-seeds/v1 manifests for the Ascent (ASC) catalog, ported from AthleteAce.
  # A record is identified by its entity URI (MIC-ASC-<code>) or a declared alias, never by its
  # name: two records with different URIs stay two records, however alike they look. Missing
  # records are created, existing values are preserved and their differences reported, and every
  # preferred code and alias is registered in EntityCode.
  class LibraryImporter
    class Error < StandardError; end
    class MissingReference < Error; end

    MODELS = {
      "Country" => Country, "State" => State, "County" => County, "Municipality" => Municipality,
      "District" => District, "Organization" => Organization, "Party" => Party, "Position" => Position, "Office" => Office,
      "Election" => Election, "Race" => Race, "Citizen" => Citizen, "Candidacy" => Candidacy,
      "Topic" => Topic, "Issue" => Issue, "Approach" => Approach, "Stance" => Stance,
      "Channel" => Channel, "Communication" => Communication, "StanceEvidence" => StanceEvidence,
      "Image" => Image, "ImagePlacement" => ImagePlacement
    }.freeze
    JURISDICTION_OWNERS = %w[Country State County Municipality District].freeze
    SCOPE_ASSOCIATIONS = {
      "State" => %w[country], "County" => %w[state], "Municipality" => %w[state county],
      "Organization" => %w[state], "Party" => %w[state], "Office" => %w[position jurisdiction], "Election" => %w[jurisdiction year],
      "Race" => %w[election office], "Candidacy" => %w[race citizen],
      "Issue" => %w[topic], "Approach" => %w[issue], "Stance" => %w[candidacy approach],
      "Communication" => %w[channel], "StanceEvidence" => %w[stance communication],
      "ImagePlacement" => %w[image]
    }.freeze
    # The types a polymorphic reference may name, recognized by their registered code or its marker.
    # A party's code names a Party, which is stored as the Organization it is.
    POLYMORPHIC_TYPES = { [ "Channel", "owner" ] => Channel::OWNER_TYPES + %w[Party],
      [ "ImagePlacement", "subject" ] => ImagePlacement::SUBJECT_TYPES }.freeze
    # Keys that identify an uncoded record created by another seeder, so it can adopt its code.
    NATURAL_KEYS = {
      Country => %w[code], State => %w[country code], County => %w[state name],
      Municipality => %w[state name], District => %w[name], Organization => %w[state name], Party => %w[state name],
      Position => %w[title], Citizen => %w[username], Office => %w[position jurisdiction seat_code],
      Election => %w[jurisdiction election_date kind], Race => %w[election office], Candidacy => %w[race citizen],
      Topic => %w[title], Issue => %w[topic title], Approach => %w[issue title],
      Stance => %w[candidacy approach], Channel => %w[platform handle], Communication => %w[url],
      StanceEvidence => %w[stance communication], Image => %w[url], ImagePlacement => %w[image subject]
    }.freeze
    BLANK_NATURAL_KEYS = { Office => %w[seat_code] }.freeze
    NESTED_ATTRIBUTES = { "Candidacy" => %w[ballot_lines], "Communication" => %w[featured_candidacies] }.freeze
    BALLOT_LINE_KEYS = %w[label kind party].freeze
    PROTECTED_ATTRIBUTES = %w[id entity_code type created_at updated_at].freeze
    # References Ascent derives after an import rather than reading from manifests.
    DERIVED_REFERENCES = { "Candidacy" => %w[primary_candidacy], "Election" => %w[creator] }.freeze
    # Columns Ascent fills itself, such as a mock election's invented candidates, or that the
    # published contract does not offer yet, like how a historical race was decided.
    UNSEEDED_ATTRIBUTES = { "Citizen" => %w[fictional], "Race" => %w[decided_by] }.freeze
    EMPTY_REPORT = { created: [], unchanged: [], conflicts: [], aliases_added: [], ballot_lines_added: [], features_added: [], primary_candidates_added: [] }.freeze

    CITIZEN_DISAMBIGUATOR = /_[2-9][A-HJ-NP-Z]\z/
    FULL_CITIZEN_CODE = /\ACITIZEN-[A-Z0-9]+(?:_[A-Z0-9]+)*#{CITIZEN_DISAMBIGUATOR.source}/

    attr_reader :report

    # The columns a model's belongs_to associations fill, which manifests set through references.
    # Other columns ending in _id, like a communication's platform_id, are ordinary attributes.
    def self.seeded_reference?(type, model, name)
      model.reflect_on_association(name.to_sym)&.macro == :belongs_to && !DERIVED_REFERENCES.fetch(type, []).include?(name.to_s)
    end

    def self.association_columns(model)
      model.reflect_on_all_associations(:belongs_to).flat_map do |association|
        [ association.foreign_key.to_s, (association.foreign_type.to_s if association.polymorphic?) ].compact
      end
    end

    def initialize(namespace: "MIC", catalog: "ASC")
      @namespace, @catalog = namespace, catalog
      @report = empty_report
    end

    def read(paths)
      reader = MICharismaSeeders::Reader.new
      paths.flat_map { |path| reader.read(path) }
    end

    # A read-only preflight of the envelope, types, attributes, and code collisions.
    def validate(paths)
      records = read(paths)
      validate_records!(records)
      { records: records.length, codes: @reference_types.length, files: paths.length }
    end

    def call(paths)
      @report = empty_report
      records = read(paths)
      validate_records!(records)
      ApplicationRecord.transaction do
        load_bindings
        pending = records
        until pending.empty?
          deferred = []
          reasons = []
          pending.each do |record|
            import_record(record)
          rescue MissingReference => e
            deferred << record
            reasons << e.message
          end
          raise Error, "Unresolved seed dependencies:\n#{reasons.uniq.join("\n")}" if deferred.length == pending.length

          pending = deferred
        end
        report[:primary_candidates_added] = Race.gather_primary_candidates!.map(&:name)
      end
      report
    rescue StandardError
      @report = empty_report
      raise
    ensure
      @bindings = @records = nil
    end

    def resolve_code(type, code, allow_name_code: true)
      model = MODELS.fetch(type) { raise Error, "Unsupported entity type #{type}" }
      binding = binding_for(local_code(code))
      if binding
        raise Error, "#{code} identifies #{binding.record_type}, not #{type}" unless same_kind?(binding.record_type, model)

        target = cached_record(binding.canonical_code) { binding.resolved_record || model.find_by(entity_code: binding.canonical_code) }
        if target
          raise Error, "#{code} identifies #{target.class.name}, not #{type}" unless target.is_a?(model)

          return target
        end
      end
      model.find_by(entity_code: local_code(code)) || (citizen_by_name_code(local_code(code)) if type == "Citizen" && allow_name_code)
    end


    private

    def empty_report
      EMPTY_REPORT.transform_values(&:dup)
    end

    # During an import every binding in the catalog is held in memory, along with the records
    # it has resolved, so a manifest's thousands of references do not each query the database.
    def load_bindings
      @bindings = EntityCode.where(namespace: @namespace, catalog: @catalog).index_by(&:code)
      @records = {}
    end

    def binding_for(code)
      return @bindings[code] if @bindings

      EntityCode.find_by(namespace: @namespace, catalog: @catalog, code: code)
    end

    # CITIZEN-JAMES_LT names the one citizen whose code adds a disambiguator to JAMES_LT.
    def citizen_by_name_code(code)
      return if code.match?(CITIZEN_DISAMBIGUATOR)

      matches = codes_starting("#{code}_").select { |candidate| candidate.delete_prefix(code).match?(/\A#{CITIZEN_DISAMBIGUATOR.source}/) }
                                          .map { |candidate| binding_for(candidate).canonical_code }.uniq
      raise Error, "#{code} could be #{matches.sort.join(" or ")}; use the full code" if matches.many?

      resolve_code("Citizen", matches.first) if matches.one?
    end

    # A code's binding records its record's base class, so a party's binding says Organization.
    def same_kind?(record_type, model)
      record_type.safe_constantize&.base_class == model.base_class
    end

    def codes_starting(prefix)
      return @bindings.keys.select { it.start_with?(prefix) } if @bindings

      EntityCode.where(namespace: @namespace, catalog: @catalog).where("code LIKE ?", "#{EntityCode.sanitize_sql_like(prefix)}%").pluck(:code)
    end

    def cached_record(canonical_code)
      return yield unless @records

      @records[canonical_code] ||= yield
    end

    def validate_records!(records)
      declared = {}
      parents = {}
      root = lambda do |code|
        parents[code] ||= code
        parents[code] = root.call(parents[code]) unless parents[code] == code
        parents[code]
      end
      records.each do |record|
        validate_record!(record)
        ([ record.code ] + record.aliases).each do |code|
          raise Error, "#{record.location}: #{code} identifies multiple types" if declared[code] && declared[code].type != record.type

          declared[code] ||= record
          parents[root.call(code)] = root.call(record.code)
        end
      end
      @reference_types = declared.transform_values(&:type)
      records.group_by { |record| root.call(record.code) }.each_value do |definitions|
        merged_attributes = {}
        merged_references = {}
        definitions.each do |record|
          desired_attributes(record).merge(nested_attributes(record)).each do |key, value|
            if merged_attributes.key?(key) && merged_attributes[key] != value
              raise Error, "#{record.location}: contradictory #{record.code} attribute #{key} across seed definitions"
            end
            merged_attributes[key] = value
          end
          (SCOPE_ASSOCIATIONS.fetch(record.type, []) + record.references.keys).uniq.each do |key|
            next unless record.references.key?(key) || record.scope.key?(key)

            reference = record.references.key?(key) ? record.references[key] : record.scope[key]
            reference = local_code(reference.is_a?(Hash) ? reference.fetch("code") : reference)
            reference = root.call(reference) if parents.key?(reference)
            if merged_references.key?(key) && merged_references[key] != reference
              raise Error, "#{record.location}: contradictory #{record.code} reference #{key} across seed definitions"
            end
            merged_references[key] = reference
          end
        end
      end
    end

    def validate_record!(record)
      unless record.namespace == @namespace && record.catalog == @catalog
        raise Error, "#{record.location}: unexpected namespace/catalog #{record.namespace}/#{record.catalog}"
      end
      model = MODELS.fetch(record.type) { raise Error, "#{record.location}: unsupported type #{record.type}" }
      ([ record.code ] + record.aliases).each do |code|
        unless code.is_a?(String) && code.match?(/\A[A-Z0-9]+(?:[-_][A-Z0-9]+)*\z/) && code == local_code(code)
          raise Error, "#{record.location}: invalid local entity code #{code.inspect}"
        end
      end
      if record.type == "Citizen"
        unless record.code.match?(FULL_CITIZEN_CODE)
          raise Error, "#{record.location}: Citizen definition #{record.code} requires a disambiguator; bare name codes are allowed only as references"
        end
        username = record.attributes["username"]
        if record.attributes["username_status"] == "provisional" && username != record.code.delete_prefix("CITIZEN-").downcase
          raise Error, "#{record.location}: Citizen #{record.code} provisional username #{username.inspect} does not match its code"
        end
      end
      record.attributes.each_key do |key|
        next if NESTED_ATTRIBUTES.fetch(record.type, []).include?(key)

        if PROTECTED_ATTRIBUTES.include?(key) || self.class.association_columns(model).include?(key) || !model.column_names.include?(key)
          raise Error, "#{record.location}: unsupported #{record.type} attribute #{key}; associations use references"
        end
      end
      record.references.each_key do |key|
        raise Error, "#{record.location}: unsupported #{record.type} reference #{key}" unless self.class.seeded_reference?(record.type, model, key)
      end
      validate_ballot_lines!(record) if record.attributes.key?("ballot_lines")
      if record.attributes.key?("featured_candidacies") && !(record.attributes["featured_candidacies"].is_a?(Array) && record.attributes["featured_candidacies"].all?(String))
        raise Error, "#{record.location}: featured_candidacies must be a list of candidacy codes"
      end
      sequences = [ record.entity_sequence ] + record.references.values.filter_map { |reference| reference["entity_sequence"] if reference.is_a?(Hash) }
      if sequences.compact.any?
        raise Error, "#{record.location}: entity-sequence lookups are not supported by the Ascent importer yet; use exact codes"
      end
    end

    def validate_ballot_lines!(record)
      lines = record.attributes["ballot_lines"]
      raise Error, "#{record.location}: ballot_lines must be a list" unless lines.is_a?(Array)

      lines.each do |line|
        unless line.is_a?(Hash) && line["label"].is_a?(String) && line["label"].present? && (line.keys - BALLOT_LINE_KEYS).empty?
          raise Error, "#{record.location}: each ballot line needs a label and may only set #{BALLOT_LINE_KEYS.join(", ")}"
        end
        raise Error, "#{record.location}: unknown ballot line kind #{line["kind"]}" if line["kind"] && !BallotLine::KINDS.include?(line["kind"])
      end
      labels = lines.map { |line| line["label"] }
      raise Error, "#{record.location}: duplicate ballot line labels" if labels.uniq.length != labels.length
    end

    # Every reference, including a place's parent jurisdiction and its ballot lines' parties,
    # resolves before anything is written, so a record retried for a missing dependency never
    # leaves a partial write behind.
    def import_record(record)
      model = MODELS.fetch(record.type)
      desired = desired_attributes(record).merge(associations_for(record))
      parent = jurisdiction_parent(record, desired) if JURISDICTION_OWNERS.include?(record.type)
      lines = resolved_ballot_lines(record) if record.attributes.key?("ballot_lines")
      featured = record.attributes["featured_candidacies"]&.map { |code| required_code("Candidacy", code, record) }
      codes = ([ record.code ] + record.aliases).uniq
      bindings = codes.filter_map { |code| binding_for(code) }
      bindings.each do |binding|
        raise Error, "#{binding.code} already identifies #{binding.record_type}" unless same_kind?(binding.record_type, model)
      end
      targets = codes.filter_map { |code| resolve_code(record.type, code, allow_name_code: false) }.uniq(&:id)
      raise Error, "#{record.location}: aliases identify different #{record.type} records" if targets.length > 1

      target = targets.first || natural_target(model, desired)
      canonical_code = target&.entity_code.presence || bindings.first&.canonical_code || record.code
      codes |= [ canonical_code ]
      if target.nil?
        refuse_second_uri!(model, desired, record)
        target = model.create!(desired.merge(entity_code: canonical_code))
        report[:created] << canonical_code
      elsif target.try(:primary_candidacy)
        # The data now places a primary candidate in this race, so the off-ballot candidacy made for
        # them takes the data's fields and keeps its ratings.
        target.update!(desired.merge(entity_code: canonical_code, primary_candidacy: nil))
        report[:created] << canonical_code
      else
        differences = desired.each_with_object({}) do |(key, value), result|
          current = comparison_value(model, key, target.public_send(key))
          incoming = comparison_value(model, key, value)
          result[key] = { existing: current, incoming: incoming } unless current == incoming
        end
        # Adoption via a natural key does not change the record's other fields.
        target.update!(entity_code: canonical_code) if target.entity_code.blank?
        if differences.empty?
          report[:unchanged] << canonical_code
        else
          report[:conflicts] << { code: canonical_code, differences: differences, source: record.source }
        end
      end
      target.jurisdiction || target.create_jurisdiction!(parent: parent) if JURISDICTION_OWNERS.include?(record.type)
      import_ballot_lines(target, lines, record, canonical_code) if lines
      import_features(target, featured, canonical_code) if featured
      register_codes(codes, canonical_code, target)
    end

    def register_codes(codes, canonical_code, target)
      @records[canonical_code] = target if @records
      codes.each do |code|
        binding = binding_for(code) || EntityCode.new(namespace: @namespace, catalog: @catalog, code: code)
        raise Error, "#{code} is permanently bound to #{binding.canonical_code}" if binding.persisted? && binding.canonical_code != canonical_code

        report[:aliases_added] << code if binding.new_record? && code != canonical_code
        binding.assign_attributes(canonical_code: canonical_code, record: target)
        binding.save! if binding.new_record? || binding.changed?
        @bindings[code] = binding if @bindings
      end
    end

    # Lines are added, never removed, so a partial capture cannot clear another line.
    # A differing existing line is reported rather than changed.
    def import_ballot_lines(candidacy, lines, record, canonical_code)
      existing_lines = candidacy.ballot_lines.index_by(&:label)
      lines.each.with_index(1) do |line, position|
        existing = existing_lines[line["label"]]
        if existing.nil?
          candidacy.ballot_lines.create!(line.merge("position" => position))
          report[:ballot_lines_added] << "#{canonical_code}: #{line["label"]}"
        else
          incoming = { "kind" => line["kind"], "party" => line["party"]&.id }
          current = { "kind" => existing.kind, "party" => existing.party_id }
          next if incoming == current

          report[:conflicts] << { code: canonical_code, ballot_line: line["label"], differences: { existing: current, incoming: incoming }, source: record.source }
        end
      end
    end

    # Definitions are compared as declared, so validation needs no database lookups.
    # Featured candidacies are added, never removed, like ballot lines.
    def import_features(communication, candidacies, canonical_code)
      existing = communication.communication_features.pluck(:candidacy_id)
      candidacies.reject { |candidacy| existing.include?(candidacy.id) }.each do |candidacy|
        communication.communication_features.create!(candidacy: candidacy)
        report[:features_added] << "#{canonical_code}: #{candidacy.entity_code}"
      end
    end

    def nested_attributes(record)
      record.attributes.slice(*NESTED_ATTRIBUTES.fetch(record.type, []))
    end

    def resolved_ballot_lines(record)
      record.attributes["ballot_lines"].map do |line|
        party = required_code("Party", line["party"], record) if line["party"]
        { "label" => line["label"], "kind" => line["kind"] || (party ? "party" : "unclassified"), "party" => party }
      end
    end

    # A place nests under the jurisdiction of the place that contains it; a District's comes from its state scope.
    def jurisdiction_parent(record, desired)
      parent_owner = case record.type
      when "State" then desired["country"]
      when "County" then desired["state"]
      when "Municipality" then desired["parent_municipality"] || desired["county"] || desired["state"]
      when "District" then (scoped_owner("State", "state", record) if record.scope["state"])
      end
      parent_owner && jurisdiction_of(parent_owner)
    end

    # A place created by another seeder may still lack its jurisdiction.
    def jurisdiction_of(owner)
      return owner.jurisdiction if owner.jurisdiction

      parent_owner = case owner
      when State then owner.country
      when County then owner.state
      when Municipality then owner.parent_municipality || owner.county || owner.state
      end
      owner.create_jurisdiction!(parent: parent_owner && jurisdiction_of(parent_owner))
    end

    def cast_attributes(model, attributes)
      attributes.to_h do |key, value|
        column = model.columns_hash.fetch(key)
        if (values = model.defined_enums[key])
          raise Error, "#{model.name}.#{key} must be one of #{values.keys.join(", ")}" unless value.nil? || values.key?(value.to_s)
        elsif column.type == :date && !value.nil?
          value = Date.iso8601(value.to_s)
        elsif column.type == :integer && !value.nil? && !value.to_s.match?(/\A-?\d+\z/)
          raise Error, "#{model.name}.#{key} requires an integer"
        end
        [ key, model.type_for_attribute(key).cast(value) ]
      end
    rescue ArgumentError => e
      raise Error, "Invalid attribute for #{model.name}: #{e.message}"
    end

    def desired_attributes(record)
      model = MODELS.fetch(record.type)
      attributes = cast_attributes(model, record.attributes.except(*NESTED_ATTRIBUTES.fetch(record.type, [])))
      attributes["status"] = "active" if record.type == "Race" && attributes["status"] == "upcoming"
      attributes
    end

    def associations_for(record)
      model = MODELS.fetch(record.type)
      values = {}
      SCOPE_ASSOCIATIONS.fetch(record.type, []).each do |key|
        reference = record.references[key] || record.scope[key]
        values[key] = resolve_reference(model, key, reference, record) if reference
      end
      record.references.each do |key, reference|
        values[key] = reference.nil? ? nil : resolve_reference(model, key, reference, record)
      end
      values
    end

    def resolve_reference(model, key, reference, record)
      if reference.is_a?(Hash)
        if (reference["namespace"] && reference["namespace"] != @namespace) || (reference["catalog"] && reference["catalog"] != @catalog)
          raise Error, "#{record.location}: foreign references need an adapter for their catalog"
        end
        reference = reference.fetch("code")
      end
      association = model.reflect_on_association(key.to_sym)
      return required_code(polymorphic_type(model, key, reference, record), reference, record) if association.polymorphic?

      case association.klass.name
      when "Jurisdiction" then jurisdiction_of(owner_for(reference, record))
      when "Year" then year_for(reference, record)
      else required_code(association.klass.name, reference, record)
      end
    end

    def polymorphic_type(model, key, code, record)
      allowed = POLYMORPHIC_TYPES.fetch([ model.name, key ]) { raise Error, "Unsupported polymorphic reference #{model.name}.#{key}" }
      code = local_code(code)
      type = binding_for(code)&.record_type || @reference_types[code] ||
             allowed.find { |candidate| code.start_with?("#{candidate.upcase}-") }
      raise Error, "#{record.location}: #{code} is not a #{allowed.join(", ")} code for #{model.name}.#{key}" unless allowed.include?(type)

      type
    end

    # A jurisdiction is referenced by the code of the place that owns it.
    def owner_for(code, record)
      code = local_code(code)
      type = EntityCode.find_by(namespace: @namespace, catalog: @catalog, code: code)&.record_type ||
             @reference_types[code] ||
             JURISDICTION_OWNERS.find { |owner| code.start_with?("#{owner.upcase}-") }
      raise Error, "#{record.location}: #{code} does not identify a jurisdiction" unless JURISDICTION_OWNERS.include?(type)

      required_code(type, code, record)
    end

    def scoped_owner(type, key, record)
      required_code(type, record.scope.fetch(key), record)
    end

    # Years are not coded; YEAR-2026 names the year itself.
    def year_for(code, record)
      number = local_code(code)[/\AYEAR-(\d{4})\z/, 1] or raise Error, "#{record.location}: invalid year reference #{code}"
      Year.find_by(year: number.to_i) || raise(MissingReference, "#{record.location}: missing Year #{number}")
    end

    def required_code(type, code, record)
      resolve_code(type, code) || raise(MissingReference, "#{record.location}: missing #{type} #{code}")
    end

    # A record that another seeder made without a URI can be claimed once by its natural key.
    # A record that already has a URI is a different entity, so it is never claimed this way.
    def natural_target(model, desired)
      return unless natural_key_complete?(model, desired)

      model.where(entity_code: [ nil, "" ]).find_by(natural_key(model, desired))
    end

    def natural_key_complete?(model, desired)
      keys = NATURAL_KEYS[model]
      return false unless keys

      blank_allowed = BLANK_NATURAL_KEYS.fetch(model, [])
      keys.all? { |key| desired[key].present? || desired.key?(key) && desired[key] == false || blank_allowed.include?(key) }
    end

    def natural_key(model, desired)
      NATURAL_KEYS.fetch(model).to_h { |key| [ key, desired[key] ] }
    end

    # Some natural keys can name only one record, such as a channel's platform and handle or a
    # communication's URL. A new URI for that record must be declared as an alias of its code.
    def refuse_second_uri!(model, desired, record)
      return unless natural_key_complete?(model, desired) && unique_natural_key?(model)

      existing = model.where.not(entity_code: [ nil, "" ]).find_by(natural_key(model, desired))
      return unless existing

      raise Error, "#{record.location}: #{record.code} names the same #{record.type} as #{existing.entity_code}; " \
                   "use that code or list #{record.code} in its aliases"
    end

    def unique_natural_key?(model)
      @unique_natural_keys ||= {}
      @unique_natural_keys.fetch(model) do
        columns = NATURAL_KEYS.fetch(model).map { |key| model.reflect_on_association(key.to_sym)&.foreign_key&.to_s || key }
        @unique_natural_keys[model] = model.connection.indexes(model.table_name).any? { |index| index.unique && index.columns.sort == columns.sort }
      end
    end

    def comparison_value(model, key, value)
      association = model.reflect_on_association(key.to_sym)
      return value unless association&.macro == :belongs_to
      return unless value

      association.polymorphic? ? [ value.class.name, value.id ] : value.id
    end

    def local_code(code)
      prefix = "#{@namespace}-#{@catalog}-"
      code.to_s.start_with?(prefix) ? code.to_s.delete_prefix(prefix) : code.to_s
    end
  end
end

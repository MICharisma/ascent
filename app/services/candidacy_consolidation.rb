class CandidacyConsolidation
  class Conflict < StandardError; end

  PROFILE_FIELDS = %w[status announcement_date platform_summary].freeze
  CHILDREN = [ Rating, RatingArchive, BallotLine, Endorsement, Stance, CommunicationFeature, OfficialResult ].freeze
  LINKS = { Channel => [ :owner_type, :owner_id ], Engagement => [ :engageable_type, :engageable_id ],
    ImagePlacement => [ :subject_type, :subject_id ] }.freeze

  def self.preview
    citizens = CitizenMerge.distinct.pluck(:citizen_id)
    groups = Candidacy.where(citizen_id: citizens).order(:id).group_by { [ it.citizen_id, it.race_id ] }.values.select { it.size > 1 }
    { "format" => "ascent-candidacy-consolidation/v1", "groups" => groups.map { new(it.map(&:id)).plan }.sort_by { it.fetch("survivor_id") } }
  end

  def self.apply(plan, performed_by:)
    raise ArgumentError, "unsupported consolidation plan" unless plan["format"] == "ascent-candidacy-consolidation/v1"
    raise ArgumentError, "performed_by is required" if performed_by.blank?
    groups = plan.fetch("groups")
    results = Candidacy.transaction do
      ids = groups.flat_map { [ it.fetch("survivor_id"), *it.fetch("duplicate_ids") ] }
      Candidacy.where(id: ids).order(:id).lock.load
      operations = groups.map do |expected|
        complete = CandidacyMerge.where(old_candidacy_id: expected.fetch("duplicate_ids")).to_a
        if complete.size == expected.fetch("duplicate_ids").size
          raise Conflict, "completed candidacy merge differs from the plan" unless complete.all? { it.candidacy_id == expected.fetch("survivor_id") }
          [ expected, nil ]
        else
          operation = new([ expected.fetch("survivor_id"), *expected.fetch("duplicate_ids") ])
          operation.scopes.each_value { it.order(:id).lock.load }
          raise Conflict, "candidacies changed since preview; generate a new plan" unless operation.plan == expected
          [ expected, operation ]
        end
      end
      snapshots = operations.map { |_, operation| operation&.snapshot }
      operations.each_with_index.map do |(expected, operation), index|
        if operation
          operation.consolidate(expected, snapshot: snapshots[index], performed_by: performed_by)
          expected.merge("status" => "applied")
        else
          expected.merge("status" => "already_applied")
        end
      end
    end
    groups.map { it.fetch("race_id") }.uniq.each do |id|
      %w[resident visitor].each { |group| Rails.cache.delete([ "race-results-v2", id, group, Time.current.beginning_of_hour.to_i ]) }
    end
    results
  end

  def initialize(ids)
    @ids = ids.sort
  end

  def plan
    rows = Candidacy.where(id: ids).order(:id).to_a
    raise Conflict, "a consolidation needs at least two existing candidacies" unless rows.size == ids.size && rows.size > 1
    raise Conflict, "candidacies must share their Citizen and race" unless rows.map { [ it.citizen_id, it.race_id ] }.uniq.one?
    PROFILE_FIELDS.each do |field|
      raise Conflict, "conflicting candidacy #{field}" if rows.filter_map { it[field].presence }.uniq.size > 1
    end
    survivor = rows.min_by { [ it.primary_candidacy_id.nil? && it.participation == "active" ? 0 : 1, it.entity_code.present? ? 0 : 1, it.id ] }
    participations = rows.map(&:participation).uniq.sort
    if participations.size > 1 && !(participations == %w[active off_ballot] && survivor.primary_candidacy_id.nil? && rows.reject { it == survivor }.all? { it.primary_candidacy_id.present? && it.participation == "off_ballot" })
      raise Conflict, "conflicting candidacy participation"
    end
    if rows.all?(&:primary_candidacy_id) && rows.map(&:primary_candidacy_id).uniq.size > 1
      raise Conflict, "conflicting primary candidacies"
    end
    { "survivor_id" => survivor.id, "duplicate_ids" => ids - [ survivor.id ], "citizen_id" => survivor.citizen_id,
      "race_id" => survivor.race_id, "name" => survivor.citizen.full_name,
      "codes" => rows.map { { "id" => it.id, "code" => it.entity_code, "participation" => it.participation } },
      "snapshot_digest" => Digest::SHA256.hexdigest(JSON.generate(snapshot)) }
  end

  def scopes
    rows = Candidacy.where(id: ids)
    result = { "candidacies" => rows, "codes" => EntityCode.where(record_type: "Candidacy", record_id: ids),
      "generals" => Candidacy.where(primary_candidacy_id: ids), "drafts" => MountainDraft.where(race_id: rows.select(:race_id)) }
    CHILDREN.each { |model| result[model.table_name] = model.where(candidacy_id: ids) }
    LINKS.each { |model, (type, key)| result[model.table_name] = model.where(type => "Candidacy", key => ids) }
    result
  end

  def snapshot
    scopes.transform_values { it.order(:id).map(&:attributes).as_json }
  end

  def consolidate(expected, snapshot:, performed_by:)
    survivor = Candidacy.find(expected.fetch("survivor_id"))
    expected.fetch("duplicate_ids").each do |id|
      source = Candidacy.find(id)
      PROFILE_FIELDS.each { |field| survivor[field] = source[field] if survivor[field].blank? && source[field].present? }
      line_ids = move_ballot_lines(source, survivor)
      move_rows(source.endorsements, survivor, unique: %w[endorser_type endorser_id kind]) do |row, changes|
        changes["ballot_line_id"] = line_ids.fetch(row.ballot_line_id, row.ballot_line_id)
      end
      source.ballot_lines.where(id: line_ids.keys).delete_all
      move_rows(source.ratings, survivor, unique: %w[voter_id])
      source.rating_archives.update_all(candidacy_id: survivor.id)
      move_rows(source.stances, survivor, unique: %w[approach_id], reject_duplicates: true)
      move_rows(source.communication_features, survivor, unique: %w[communication_id])
      move_rows(source.official_results, survivor, unique: %w[race_id])
      LINKS.each do |model, (type, key)|
        unique = case model.name
        when "Engagement" then %w[voter_id kind]
        when "ImagePlacement" then %w[image_id]
        else []
        end
        move_rows(model.where(type => "Candidacy", key => id), survivor, key: key.to_s, unique: unique, fixed: { type.to_s => "Candidacy" })
      end
      source.general_candidacies.update_all(primary_candidacy_id: survivor.id)
      move_drafts(source, survivor)
      EntityCode.where(record_type: "Candidacy", record_id: id).update_all(record_id: survivor.id, canonical_code: survivor.entity_code, updated_at: Time.current)
      CandidacyMerge.where(candidacy_id: id).update_all(candidacy_id: survivor.id, updated_at: Time.current)
      CandidacyMerge.create!(old_candidacy_id: id, candidacy: survivor, performed_by: performed_by, snapshot: snapshot)
      source.delete
    end
    survivor.save!
  end

  private

  attr_reader :ids

  def move_ballot_lines(source, survivor)
    source.ballot_lines.each_with_object({}) do |line, duplicates|
      existing = survivor.ballot_lines.find_by(label: line.label)
      if existing
        raise Conflict, "conflicting ballot line #{line.label}" unless line.attributes.slice("kind", "party_id") == existing.attributes.slice("kind", "party_id")
        duplicates[line.id] = existing.id
      else
        line.update_columns(candidacy_id: survivor.id)
      end
    end
  end

  def move_rows(scope, survivor, key: "candidacy_id", unique:, fixed: {}, reject_duplicates: false)
    scope.order(:id).each do |row|
      changes = { key => survivor.id }
      yield(row, changes) if block_given?
      existing = scope.klass.find_by(row.attributes.slice(*unique).merge(fixed).merge(key => survivor.id)) if unique.any?
      if existing
        ignored = [ "id", "entity_code", key, "created_at", "updated_at", "position" ]
        raise Conflict, "conflicting #{row.class.name} #{row.id}" if reject_duplicates || row.attributes.merge(changes).except(*ignored) != existing.attributes.except(*ignored)
        row.delete
      else
        row.update_columns(changes)
      end
    end
  end

  def move_drafts(source, survivor)
    MountainDraft.where(race_id: survivor.race_id).lock.each do |draft|
      values = draft.ratings.dup
      next unless values.key?(source.id.to_s)
      value = values.delete(source.id.to_s)
      if values.key?(survivor.id.to_s) && values[survivor.id.to_s] != value
        raise Conflict, "conflicting draft ratings for voter #{draft.voter_id}"
      end
      values[survivor.id.to_s] = value
      draft.update_columns(ratings: values)
    end
  end
end

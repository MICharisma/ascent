class CitizenConsolidation
  class Conflict < StandardError; end

  PROFILE_FIELDS = %w[email birth_date bio].freeze
  LINKS = { Channel => [ :owner_type, :owner_id ], Endorsement => [ :endorser_type, :endorser_id ],
    Engagement => [ :engageable_type, :engageable_id ], ImagePlacement => [ :subject_type, :subject_id ] }.freeze
  UNIQUE_LINKS = { Endorsement => %w[candidacy_id kind], Engagement => %w[voter_id kind], ImagePlacement => %w[image_id] }.freeze

  def self.preview
    entities = RizzSync.where(state: "merge_needed").distinct.pluck(:rizz_entity_id)
    { "format" => "ascent-citizen-consolidation/v1", "groups" => entities.sort.map { new(it).plan } }
  end

  def self.apply(plan, performed_by:)
    raise ArgumentError, "unsupported consolidation plan" unless plan["format"] == "ascent-citizen-consolidation/v1"
    raise ArgumentError, "performed_by is required" if performed_by.blank?

    plan.fetch("groups").map { |group| new(group.fetch("rizz_entity_id")).apply(group, performed_by: performed_by) }
  end

  def initialize(entity_id)
    @entity_id = entity_id
  end

  def plan
    syncs = RizzSync.where(rizz_entity_id: entity_id).order(:citizen_id).to_a
    holders = syncs.select { it.state == "synced" }
    raise Conflict, "#{entity_id} must have exactly one synced Citizen" unless holders.one?
    raise Conflict, "#{entity_id} contains an unresolved sync" unless syncs.all? { %w[synced merge_needed].include?(it.state) }

    survivor = holders.first.citizen
    ids = syncs.map(&:citizen_id)
    citizens = Citizen.where(id: ids).order(:id).to_a
    raise Conflict, "#{entity_id} contains a fictional Citizen" if citizens.any?(&:fictional)
    raise Conflict, "#{entity_id} code differs from its holder" unless syncs.all? { it.rizz_code == survivor.entity_code }
    profiles = PROFILE_FIELDS.to_h { |field| [ field, citizens.filter_map { it.public_send(field).presence }.uniq ] }
    raise Conflict, "#{entity_id} has conflicting profile fields" if profiles.values.any? { it.size > 1 }
    snapshot = snapshot_for(ids)
    same_race = Candidacy.where(citizen_id: ids).order(:id).group_by(&:race_id).values.select { it.size > 1 }.map { it.map(&:id) }
    if same_race.any? { |group| Candidacy.where(id: group).where.not(primary_candidacy_id: nil).count > 1 }
      raise Conflict, "#{entity_id} has overlapping primary-derived candidacies"
    end
    { "rizz_entity_id" => entity_id, "survivor_id" => survivor.id, "duplicate_ids" => ids - [ survivor.id ],
      "names" => citizens.map { { "id" => it.id, "name" => it.full_name, "code" => it.entity_code } },
      "same_race_candidacies" => same_race, "snapshot_digest" => Digest::SHA256.hexdigest(JSON.generate(snapshot)) }
  end

  def apply(expected, performed_by:)
    old_ids = expected.fetch("duplicate_ids")
    completed = CitizenMerge.where(old_citizen_id: old_ids).to_a
    if completed.size == old_ids.size
      unless completed.all? { it.citizen_id == expected.fetch("survivor_id") && it.rizz_entity_id == entity_id }
        raise Conflict, "completed merge differs from the plan"
      end
      return expected.merge("status" => "already_applied")
    end

    Citizen.transaction do
      ids = [ expected.fetch("survivor_id"), *old_ids ]
      Citizen.where(id: ids).order(:id).lock.load
      RizzSync.where(citizen_id: ids).order(:citizen_id).lock.load
      raise Conflict, "#{entity_id} changed since preview; generate a new plan" unless plan == expected

      survivor = Citizen.find(expected.fetch("survivor_id"))
      snapshot = snapshot_for(ids)
      old_ids.each do |id|
        source = Citizen.find(id)
        PROFILE_FIELDS.each { |field| survivor[field] = source[field] if survivor[field].blank? && source[field].present? }
        source.candidacies.update_all(citizen_id: survivor.id, updated_at: Time.current)
        move_links(source, survivor)
        EntityCode.where(record_type: "Citizen", record_id: id).update_all(record_id: survivor.id, canonical_code: survivor.entity_code, updated_at: Time.current)
        CitizenMerge.where(citizen_id: id).update_all(citizen_id: survivor.id, updated_at: Time.current)
        CitizenMerge.create!(old_citizen_id: id, citizen: survivor, rizz_entity_id: entity_id, performed_by: performed_by, snapshot: snapshot)
        source.rizz_names.delete_all
        source.rizz_sync.delete
        source.name_reading&.delete
        source.delete
      end
      survivor.save!
      expected.merge("status" => "applied")
    end
  end

  private

  attr_reader :entity_id

  def snapshot_for(ids)
    models = { "citizens" => Citizen.where(id: ids), "candidacies" => Candidacy.where(citizen_id: ids),
      "codes" => EntityCode.where(record_type: "Citizen", record_id: ids), "syncs" => RizzSync.where(citizen_id: ids),
      "readings" => CitizenNameReading.where(citizen_id: ids), "names" => RizzName.where(citizen_id: ids) }
    LINKS.each { |model, (type, key)| models[model.table_name] = model.where(type => "Citizen", key => ids) }
    models.transform_values { |scope| scope.order(:id).map(&:attributes).as_json }
  end

  def move_links(source, survivor)
    LINKS.each do |model, (type, key)|
      model.where(type => "Citizen", key => source.id).find_each do |row|
        fields = UNIQUE_LINKS[model]
        existing = model.find_by(row.attributes.slice(*fields).merge(type => "Citizen", key => survivor.id)) if fields
        if existing
          differences = row.attributes.except("id", key.to_s, "created_at", "updated_at", "position") !=
            existing.attributes.except("id", key.to_s, "created_at", "updated_at", "position")
          raise Conflict, "#{model.name} #{row.id} conflicts with #{existing.id}" if differences
          row.delete
        else
          row.update!(key => survivor.id)
        end
      end
    end
  end
end

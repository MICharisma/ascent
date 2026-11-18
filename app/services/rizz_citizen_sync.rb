# Sends a Citizen's names and candidacies to Rizz and takes up the code Rizz
# assigns. Seeding never calls Rizz; this runs as its own step
# (rake rizz:sync_citizens).
#
# Each change gets a revision containing its content digest and a generation,
# so unchanged citizens are skipped and retries reuse the same revision. When Rizz
# places the citizen in an entity, the citizen adopts its MIC-RZZ code and
# keeps its Ascent code as an alias. When Rizz holds the citizen for an
# identity review, the sync records the review; syncing again after the
# decision completes it. A review that involves another app's person is
# decided by the Rizz identity authority, not by Ascent. When Rizz places two
# local citizens in one entity, the second is left for a local merge rather
# than given a code another citizen holds.
#
# A name whose columns take a shape Rizz reads on its own (Rizz::Ascent::
# NameShape) goes as it is, and Rizz derives its parts. Any other name goes
# with the parts Ascent read for it (CitizenNameReading, from rake
# rizz:read_overflow) or a Rizz reviewer chose (rake rizz:review_names);
# until it has one, the sync is held.
#
# Fictional citizens from mock elections are never sent, and Voters are not
# Citizens. Needs the rizz-client gem, RIZZ_ENDPOINT and RIZZ_API_TOKEN.
class RizzCitizenSync
  # The name's parts need a reading, or triage, before the citizen goes to Rizz.
  class NameHeld < StandardError; end

  def self.client
    require "rizz-client"
    Rizz::Client.new(endpoint: ENV.fetch("RIZZ_ENDPOINT"), token: ENV.fetch("RIZZ_API_TOKEN"))
  end

  def self.citizens
    Citizen.real.includes(:rizz_sync, :name_reading, candidacies: { race: [ :office, :election ] })
  end

  def initialize(client: self.class.client)
    @client = client
  end

  def call(citizen)
    sync = citizen.rizz_sync || citizen.build_rizz_sync
    record = Rizz::Ascent::CitizenRecord.new(citizen, full_name_parts: name_parts(citizen))
    evidence = evidence_for(citizen)
    digest = Digest::SHA256.hexdigest(JSON.generate(record.to_h(source_revision: "", identity_evidence: evidence).sort.to_h))
    return sync if prepare_revision(sync, digest) == :unchanged

    revision = sync.source_revision
    attempt(sync, citizen, record, evidence, revision)
  rescue NameHeld => error
    sync.update!(state: "held", last_error: error.message.truncate(255))
    sync
  rescue ArgumentError => error
    sync.update!(state: "skipped", last_error: error.message.truncate(255))
    sync
  rescue Rizz::Unavailable, Rizz::Error => error
    sync.update!(state: "failed", source_revision: revision, last_error: "#{error.class}: #{error.message}".truncate(255))
    sync
  end

  private

  attr_reader :client

  def prepare_revision(sync, digest)
    sync.with_lock do
      stored = sync.source_revision.to_s
      current = stored == digest || stored.start_with?("#{digest}:")
      if sync.state == "synced" && current
        :unchanged
      else
        reuse = current && (stored.include?(":") || sync.rizz_entity_id.nil?)
        sync.source_revision = "#{digest}:#{SecureRandom.uuid}" unless reuse
        sync.update!(state: "pending")
        :pending
      end
    end
  end

  # Nil when Rizz can read the name columns itself; else the parts Ascent
  # read. A fictional citizen is never sent, whatever its name.
  def name_parts(citizen)
    return nil if citizen.fictional
    shape = Rizz::Ascent::NameShape.classify(citizen.first_name, citizen.middle_name, citizen.last_name)
    return nil if Rizz::Ascent::NameShape.accepted?(shape)

    reading = citizen.name_reading
    raise NameHeld, "The name needs a reading (#{shape})" unless reading&.current?
    raise NameHeld, "A reviewer found no reading fits; the name needs correcting (#{shape})" if reading.outcome == "rejected"
    raise NameHeld, "The name awaits triage (#{shape})" unless CitizenNameReading::READ.include?(reading.outcome)
    reading.parts
  end

  def attempt(sync, citizen, record, evidence, revision, retried: false)
    expected_version = sync.rizz_version if sync.rizz_entity_id
    payload = record.to_h(source_revision: revision, identity_evidence: evidence, expected_version: expected_version)
    request_key = revision.include?(":") ? Digest::SHA256.hexdigest(JSON.generate(payload)) : revision
    key = "citizen-#{citizen.id}-#{request_key}"
    result = client.import_person(payload, idempotency_key: key)
    return hold_for_review(sync, result, revision) if result["status"] == "review_required"

    place(sync, citizen, result, revision)
  rescue Rizz::Error => error
    # Another app or source record may have changed the entity since the last sync.
    raise unless error.status == 409 && sync.rizz_entity_id && !retried
    sync.rizz_version = client.entity(sync.rizz_entity_id).fetch("version")
    attempt(sync, citizen, record, evidence, revision, retried: true)
  end

  def hold_for_review(sync, result, revision)
    sync.update!(state: "review", review_id: result.fetch("review_id"), source_revision: revision, last_error: nil)
    sync
  end

  def place(sync, citizen, result, revision)
    code = result.fetch("qualified_code")
    holder = Citizen.where(entity_code: code).where.not(id: citizen.id).first ||
      RizzSync.where(rizz_entity_id: result.fetch("entity_id")).where.not(citizen_id: citizen.id).first&.citizen
    sync.assign_attributes(rizz_entity_id: result.fetch("entity_id"), rizz_version: result.fetch("version"), rizz_code: code,
      source_revision: revision, review_id: nil, synced_at: Time.current)
    if holder
      sync.update!(state: "merge_needed", last_error: "Rizz places this citizen in #{code}, which Citizen #{holder.id} holds")
    else
      Citizen.transaction do
        citizen.adopt_rizz_code!(code)
        sync.update!(state: "synced", last_error: nil)
      end
    end
    sync
  end

  # The candidacies name the citizen; their codes don't change when the citizen adopts a Rizz code.
  def evidence_for(citizen)
    candidacies = citizen.candidacies.map { it.entity_code.presence || "Candidacy #{it.id}" }.sort
    statement = candidacies.any? ? "is the candidate of #{candidacies.join(', ')}" : "has no candidacies"
    "Ascent Citizen #{citizen.id} #{statement}".truncate(512)
  end
end

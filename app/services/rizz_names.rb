# Keeps rizz_names in step with Rizz, using the client's projection sync
# (Rizz::Projection::Sync) against Ascent's own tables. Each Citizen is
# referred to by its Rizz person binding, "<RIZZ_SCOPE>:person" and its ID.
#
#   refresh(citizens)  fetch these citizens' names now
#   poll               read the event feed; clear changed rows, then refetch them
#   revalidate         refetch every real citizen (daily), which also adds rows
#                      for newly synced citizens
#
# Each returns { "referring" => :ok | :unavailable | :reset }. An outage
# changes nothing: pages keep showing the stored names.
#
# Needs the rizz-client gem, RIZZ_ENDPOINT, RIZZ_API_TOKEN and RIZZ_SCOPE.
class RizzNames
  NEUTRAL = "Citizen".freeze

  def self.enabled?
    ENV["RIZZ_ENDPOINT"].present?
  end

  def self.namespace
    "#{ENV.fetch('RIZZ_SCOPE')}:person"
  end

  def self.reference(citizen_id)
    { namespace: namespace, external_id: citizen_id.to_s }
  end

  def initialize(client: RizzCitizenSync.client)
    @syncs = RizzName::PURPOSES.to_h do |purpose|
      [ purpose, Rizz::Projection::Sync.new(client: client, store: Store.new(purpose), purpose: purpose) ]
    end
  end

  def refresh(citizens)
    references = citizens.map { self.class.reference it.id }
    each_purpose { it.refresh references }
  end

  def poll
    each_purpose(&:poll)
  end

  def revalidate
    results = Hash.new { |hash, key| hash[key] = [] }
    Citizen.real.in_batches(of: Rizz::Client::DISPLAY_BATCH_LIMIT) do |batch|
      refresh(batch.select(:id)).each { |purpose, result| results[purpose] << result }
    end
    results.transform_values { |list| list.find { it != :ok } || :ok }
  end

  private

  def each_purpose
    @syncs.transform_values { yield it }
  end

  # The store interface Rizz::Projection::Sync expects, over rizz_names and
  # rizz_feed_cursors for one purpose.
  class Store
    def initialize(purpose)
      @purpose = purpose
    end

    def get(key)
      record = rows.find_by(citizen_id: citizen_id(key))
      record && to_row(record)
    end

    def put(key, row)
      record = rows.find_or_initialize_by citizen_id: citizen_id(key)
      record.update!(
        state: row["state"], rizz_entity_id: row["entity_id"], rizz_code: row["code"], display_name: row["display_name"],
        display_parts: row["display_parts"], sort_key: row["sort_key"], name_sort: RizzName.sort_keys(row["display_name"], row["display_parts"], row["sort_key"]), search_forms: row["search_forms"] || [], form_id: row["form_id"], rule_id: row["rule_id"],
        view_version: row["view_version"], fetched_at: row["fetched_at"]
      )
    end

    def delete(key)
      rows.where(citizen_id: citizen_id(key)).delete_all
    end

    def keys
      rows.pluck(:citizen_id).map { key_for it }
    end

    def keys_for_entity(entity_id)
      rows.where(rizz_entity_id: entity_id).pluck(:citizen_id).map { key_for it }
    end

    def cursor
      RizzFeedCursor.find_by(purpose: @purpose)&.cursor
    end

    def save_cursor(cursor)
      RizzFeedCursor.find_or_initialize_by(purpose: @purpose).update! cursor: cursor
    end

    def transaction(&)
      RizzName.transaction(&)
    end

    def purge!
      rows.delete_all
    end

    private

    def rows
      RizzName.where purpose: @purpose
    end

    def key_for(citizen_id)
      Rizz::Projection.key RizzNames.reference(citizen_id)
    end

    def citizen_id(key)
      reference = JSON.parse key
      raise ArgumentError, "not an Ascent Citizen reference: #{key}" unless reference["namespace"] == RizzNames.namespace
      Integer reference.fetch("external_id")
    end

    def to_row(record)
      {
        "reference" => RizzNames.reference(record.citizen_id).transform_keys(&:to_s), "entity_id" => record.rizz_entity_id,
        "code" => record.rizz_code, "state" => record.state, "display_name" => record.display_name,
        "display_parts" => record.display_parts, "sort_key" => record.sort_key,
        "search_forms" => record.search_forms, "form_id" => record.form_id, "rule_id" => record.rule_id,
        "view_version" => record.view_version, "fetched_at" => record.fetched_at&.utc&.iso8601
      }
    end
  end
end

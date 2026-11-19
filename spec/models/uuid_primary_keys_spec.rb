# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261119120000_convert_primary_keys_and_references_to_uuid")

RSpec.describe "UUIDv7 primary keys" do
  it "mints RFC 9562 UUIDv7s on ApplicationRecord models and honors client-supplied IDs" do
    first = create(:topic)
    second = create(:topic)
    preset_id = SecureRandom.uuid_v7
    preset = create(:topic, id: preset_id)

    expect(first.id).to match(ApplicationRecord::UUID_FORMAT)
    expect(first.id[14]).to eq("7")
    expect(second.id).to match(ApplicationRecord::UUID_FORMAT)
    expect(second.id[14]).to eq("7")
    expect(second.id).to be > first.id
    expect(preset.id).to eq(preset_id)
  end

  it "mints RFC 9562 UUIDv7s on ActiveStorage records" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("png-bytes"),
      filename: "portrait.png",
      content_type: "image/png"
    )
    image = Image.create!(url: "https://example.test/portrait-#{SecureRandom.hex(4)}.png")
    image.file.attach(blob)

    expect(blob.id).to match(ApplicationRecord::UUID_FORMAT)
    expect(blob.id[14]).to eq("7")
    expect(image.file.attachment.id).to match(ApplicationRecord::UUID_FORMAT)
    expect(image.file.attachment.id[14]).to eq("7")
    expect(image.file.attachment.record_id).to eq(image.id)
  end

  it "mints RFC 9562 UUIDv7s on Ahoy visits and events linked to voters" do
    voter = create(:voter)
    visit = Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: SecureRandom.uuid, user: voter, started_at: Time.current)
    event = Ahoy::Event.create!(visit: visit, user: voter, name: "page_viewed", properties: {}, time: Time.current)

    expect(visit.id).to match(ApplicationRecord::UUID_FORMAT)
    expect(visit.id[14]).to eq("7")
    expect(event.id).to match(ApplicationRecord::UUID_FORMAT)
    expect(event.id[14]).to eq("7")
    expect(event.visit).to eq(visit)
    expect(event.user).to eq(voter)
  end

  it "keeps UUID candidacy keys and nil removals in MountainDraft#ratings_by_candidacy" do
    voter = create(:voter)
    race = create(:race, :active)
    first = create(:candidacy, race: race)
    second = create(:candidacy, race: race)

    draft = MountainDraft.new(voter: voter, race: race)
    draft.revise(ratings: { first.id => 320, second.id => "" }, baseline: 210)
    draft.save!

    expect(draft.reload.ratings_by_candidacy).to eq(first.id => 320, second.id => nil)
  end

  it "stores both legacy integer IDs and UUIDs in historical merge redirect columns" do
    citizen = create(:citizen)
    legacy = CitizenMerge.create!(old_citizen_id: "12345", citizen: citizen, rizz_entity_id: SecureRandom.uuid, performed_by: "test", snapshot: {})
    modern_id = SecureRandom.uuid_v7
    modern = CitizenMerge.create!(old_citizen_id: modern_id, citizen: citizen, rizz_entity_id: SecureRandom.uuid, performed_by: "test", snapshot: {})

    expect(CitizenMerge.find_by(old_citizen_id: "12345")).to eq(legacy)
    expect(CitizenMerge.find_by(old_citizen_id: modern_id)).to eq(modern)
  end

  it "migrates bigint tables, unconstrained refs, polymorphics, JSONB draft keys, and views in place" do
    conn = ActiveRecord::Base.connection
    schema = "uuid_migration_spec_#{SecureRandom.hex(4)}"

    conn.execute("CREATE SCHEMA #{schema}")
    previous_search_path = conn.schema_search_path
    conn.schema_search_path = schema

    conn.execute(<<~SQL)
      CREATE TABLE #{schema}.voters (
        id bigserial PRIMARY KEY,
        created_at timestamp NOT NULL DEFAULT NOW()
      );
      CREATE TABLE #{schema}.citizens (
        id bigserial PRIMARY KEY,
        created_at timestamp NOT NULL DEFAULT NOW()
      );
      CREATE TABLE #{schema}.candidacies (
        id bigserial PRIMARY KEY,
        citizen_id bigint NOT NULL REFERENCES #{schema}.citizens(id),
        primary_candidacy_id bigint REFERENCES #{schema}.candidacies(id),
        created_at timestamp NOT NULL DEFAULT NOW()
      );
      CREATE TABLE #{schema}.mountain_drafts (
        id bigserial PRIMARY KEY,
        voter_id bigint NOT NULL REFERENCES #{schema}.voters(id),
        ratings jsonb NOT NULL DEFAULT '{}'::jsonb,
        created_at timestamp NOT NULL DEFAULT NOW()
      );
      CREATE TABLE #{schema}.ahoy_visits (
        id bigserial PRIMARY KEY,
        user_id bigint,
        started_at timestamp NOT NULL DEFAULT NOW()
      );
      CREATE TABLE #{schema}.ahoy_events (
        id bigserial PRIMARY KEY,
        visit_id bigint,
        user_id bigint,
        time timestamp NOT NULL DEFAULT NOW()
      );
      CREATE TABLE #{schema}.citizen_merges (
        id bigserial PRIMARY KEY,
        old_citizen_id bigint NOT NULL,
        citizen_id bigint NOT NULL REFERENCES #{schema}.citizens(id),
        created_at timestamp NOT NULL DEFAULT NOW()
      );
      CREATE UNIQUE INDEX index_citizen_merges_old ON #{schema}.citizen_merges (old_citizen_id);
      CREATE TABLE #{schema}.rule_statements (
        id bigserial PRIMARY KEY,
        created_at timestamp NOT NULL DEFAULT NOW()
      );
      CREATE TABLE #{schema}.rule_source_links (
        id bigserial PRIMARY KEY,
        linkable_type varchar NOT NULL,
        linkable_id bigint NOT NULL,
        lu_unit_id bigint NOT NULL,
        created_at timestamp NOT NULL DEFAULT NOW()
      );
      CREATE VIEW #{schema}.sample_candidacy_view AS
        SELECT candidacies.id, candidacies.citizen_id FROM #{schema}.candidacies;
    SQL

    voter_id = conn.select_value("INSERT INTO #{schema}.voters DEFAULT VALUES RETURNING id")
    citizen_id = conn.select_value("INSERT INTO #{schema}.citizens DEFAULT VALUES RETURNING id")
    cand1_id = conn.select_value("INSERT INTO #{schema}.candidacies (citizen_id) VALUES (#{citizen_id}) RETURNING id")
    cand2_id = conn.select_value("INSERT INTO #{schema}.candidacies (citizen_id, primary_candidacy_id) VALUES (#{citizen_id}, #{cand1_id}) RETURNING id")
    conn.execute("INSERT INTO #{schema}.mountain_drafts (voter_id, ratings) VALUES (#{voter_id}, '{\"#{cand1_id}\": 350, \"#{cand2_id}\": null}'::jsonb)")
    visit_id = conn.select_value("INSERT INTO #{schema}.ahoy_visits (user_id) VALUES (#{voter_id}) RETURNING id")
    conn.execute("INSERT INTO #{schema}.ahoy_events (visit_id, user_id) VALUES (#{visit_id}, #{voter_id})")
    conn.execute("INSERT INTO #{schema}.citizen_merges (old_citizen_id, citizen_id) VALUES (998877, #{citizen_id})")
    stmt_id = conn.select_value("INSERT INTO #{schema}.rule_statements DEFAULT VALUES RETURNING id")
    conn.execute("INSERT INTO #{schema}.rule_source_links (linkable_type, linkable_id, lu_unit_id) VALUES ('Rule::Statement', #{stmt_id}, 424242)")

    migration = ConvertPrimaryKeysAndReferencesToUuid.new
    migration.suppress_messages { migration.up }

    new_voter_id = conn.select_value("SELECT id FROM #{schema}.voters")
    new_citizen_id = conn.select_value("SELECT id FROM #{schema}.citizens")
    cands = conn.select_rows("SELECT id, primary_candidacy_id FROM #{schema}.candidacies ORDER BY primary_candidacy_id NULLS FIRST")
    new_cand1_id, new_cand2_id = cands[0][0], cands[1][0]

    expect(new_voter_id).to match(ApplicationRecord::UUID_FORMAT)
    expect(cands[1][1]).to eq(new_cand1_id)

    draft_ratings = JSON.parse(conn.select_value("SELECT ratings::text FROM #{schema}.mountain_drafts"))
    expect(draft_ratings).to eq(new_cand1_id => 350, new_cand2_id => nil)

    event_row = conn.select_rows("SELECT visit_id, user_id FROM #{schema}.ahoy_events").sole
    expect(event_row).to eq([ conn.select_value("SELECT id FROM #{schema}.ahoy_visits"), new_voter_id ])

    merge_row = conn.select_rows("SELECT old_citizen_id, citizen_id FROM #{schema}.citizen_merges").sole
    expect(merge_row).to eq([ "998877", new_citizen_id ])

    link_row = conn.select_rows("SELECT linkable_id, lu_unit_id FROM #{schema}.rule_source_links").sole
    expect(link_row).to eq([ conn.select_value("SELECT id FROM #{schema}.rule_statements"), 424242 ])

    view_rows = conn.select_rows("SELECT id, citizen_id FROM #{schema}.sample_candidacy_view")
    expect(view_rows.map(&:last).uniq).to eq([ new_citizen_id ])
  ensure
    conn.schema_search_path = previous_search_path if defined?(previous_search_path) && previous_search_path
    conn.execute("DROP SCHEMA IF EXISTS #{schema} CASCADE") if defined?(schema) && schema
  end

  it "preserves btree_gist exclusion constraints and check constraints across the UUID swap" do
    conn = ActiveRecord::Base.connection
    schema = "uuid_exclusion_spec_#{SecureRandom.hex(4)}"

    conn.execute("CREATE SCHEMA #{schema}")
    previous_search_path = conn.schema_search_path
    conn.schema_search_path = "#{schema}, public"

    conn.execute(<<~SQL)
      CREATE TABLE #{schema}.mig_jurisdictions (
        id bigserial PRIMARY KEY,
        parent_id bigint REFERENCES #{schema}.mig_jurisdictions(id),
        created_at timestamp NOT NULL DEFAULT NOW(),
        CONSTRAINT mig_jurisdictions_no_self_parent CHECK (parent_id <> id)
      );
      CREATE TABLE #{schema}.mig_jurisdiction_boundaries (
        id bigserial PRIMARY KEY,
        jurisdiction_id bigint NOT NULL REFERENCES #{schema}.mig_jurisdictions(id),
        valid_from date NOT NULL,
        valid_until date,
        created_at timestamp NOT NULL DEFAULT NOW(),
        CONSTRAINT jb_no_overlap EXCLUDE USING gist (
          jurisdiction_id WITH =,
          daterange(valid_from, valid_until, '[)') WITH &&
        )
      );
    SQL

    jur_id = conn.select_value("INSERT INTO #{schema}.mig_jurisdictions DEFAULT VALUES RETURNING id")
    conn.execute("INSERT INTO #{schema}.mig_jurisdiction_boundaries (jurisdiction_id, valid_from, valid_until) VALUES (#{jur_id}, '2024-01-01', '2026-01-01')")

    migration = ConvertPrimaryKeysAndReferencesToUuid.new
    migration.suppress_messages { migration.up }

    new_jur_id = conn.select_value("SELECT id FROM #{schema}.mig_jurisdictions")
    expect(new_jur_id).to match(ApplicationRecord::UUID_FORMAT)

    expect {
      conn.transaction(requires_new: true) do
        conn.execute("INSERT INTO #{schema}.mig_jurisdiction_boundaries (jurisdiction_id, valid_from, valid_until) VALUES (#{conn.quote(new_jur_id)}, '2025-01-01', '2027-01-01')")
      end
    }.to raise_error(ActiveRecord::StatementInvalid, /jb_no_overlap/)

    expect {
      conn.transaction(requires_new: true) do
        conn.execute("UPDATE #{schema}.mig_jurisdictions SET parent_id = id WHERE id = #{conn.quote(new_jur_id)}")
      end
    }.to raise_error(ActiveRecord::StatementInvalid, /mig_jurisdictions_no_self_parent/)
  ensure
    conn.schema_search_path = previous_search_path if defined?(previous_search_path) && previous_search_path
    conn.execute("DROP SCHEMA IF EXISTS #{schema} CASCADE") if defined?(schema) && schema
  end
end

# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_21_150000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gist"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "postgis"

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.datetime "created_at", null: false
    t.uuid "blob_id", null: false
    t.uuid "record_id", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "variation_digest", null: false
    t.uuid "blob_id", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ahoy_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.jsonb "properties"
    t.datetime "time"
    t.uuid "visit_id"
    t.uuid "user_id"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["properties"], name: "index_ahoy_events_on_properties", opclass: :jsonb_path_ops, using: :gin
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_visits", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "visit_token"
    t.string "visitor_token"
    t.string "ip"
    t.text "user_agent"
    t.text "referrer"
    t.string "referring_domain"
    t.text "landing_page"
    t.string "browser"
    t.string "os"
    t.string "device_type"
    t.string "country"
    t.string "region"
    t.string "city"
    t.float "latitude"
    t.float "longitude"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_term"
    t.string "utm_content"
    t.string "utm_campaign"
    t.string "app_version"
    t.string "os_version"
    t.string "platform"
    t.datetime "started_at"
    t.uuid "user_id"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token", "started_at"], name: "index_ahoy_visits_on_visitor_token_and_started_at"
  end

  create_table "approaches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "entity_code"
    t.string "title"
    t.datetime "updated_at", null: false
    t.uuid "issue_id", null: false
    t.index ["entity_code"], name: "index_approaches_on_entity_code", unique: true
    t.index ["issue_id"], name: "index_approaches_on_issue_id"
  end

  create_table "area_of_concerns", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.string "policy_domain"
    t.string "regulatory_scope"
    t.datetime "updated_at", null: false
  end

  create_table "ballot_lines", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", default: "unclassified", null: false
    t.string "label", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.uuid "party_id"
    t.uuid "candidacy_id", null: false
    t.index ["candidacy_id", "label"], name: "index_ballot_lines_on_candidacy_id_and_label", unique: true
    t.index ["candidacy_id"], name: "index_ballot_lines_on_candidacy_id"
    t.index ["party_id"], name: "index_ballot_lines_on_party_id"
  end

  create_table "candidacies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "announcement_date"
    t.datetime "created_at", null: false
    t.string "entity_code"
    t.string "participation", default: "active", null: false
    t.text "platform_summary"
    t.string "status"
    t.datetime "updated_at", null: false
    t.uuid "citizen_id", null: false
    t.uuid "race_id", null: false
    t.uuid "primary_candidacy_id"
    t.index ["citizen_id"], name: "index_candidacies_on_citizen_id"
    t.index ["entity_code"], name: "index_candidacies_on_entity_code", unique: true
    t.index ["primary_candidacy_id"], name: "index_candidacies_on_primary_candidacy_id"
    t.index ["race_id", "citizen_id"], name: "index_candidacies_from_primaries_once_per_race_and_citizen", unique: true, where: "(primary_candidacy_id IS NOT NULL)"
    t.index ["race_id"], name: "index_candidacies_on_race_id"
  end

  create_table "candidacy_merges", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "old_candidacy_id", null: false
    t.string "performed_by", null: false
    t.jsonb "snapshot", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "candidacy_id", null: false
    t.index ["candidacy_id"], name: "index_candidacy_merges_on_candidacy_id"
    t.index ["old_candidacy_id"], name: "index_candidacy_merges_on_old_candidacy_id", unique: true
  end

  create_table "chambers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.uuid "governing_body_id", null: false
    t.index ["governing_body_id", "name"], name: "index_chambers_on_governing_body_id_and_name", unique: true
    t.index ["governing_body_id"], name: "index_chambers_on_governing_body_id"
  end

  create_table "channels", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "entity_code"
    t.string "handle", null: false
    t.boolean "official", default: false, null: false
    t.string "owner_type"
    t.string "platform", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.string "review_status", default: "pending", null: false
    t.datetime "reviewed_at"
    t.uuid "reviewed_by_id"
    t.uuid "owner_id"
    t.index ["entity_code"], name: "index_channels_on_entity_code", unique: true
    t.index ["owner_type", "owner_id"], name: "index_channels_on_owner"
    t.index ["platform", "handle"], name: "index_channels_on_platform_and_handle", unique: true
    t.index ["review_status"], name: "index_channels_on_review_status"
    t.index ["reviewed_by_id"], name: "index_channels_on_reviewed_by_id"
  end

  create_table "citizen_merges", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "old_citizen_id", null: false
    t.string "rizz_entity_id", null: false
    t.string "performed_by", null: false
    t.jsonb "snapshot", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "citizen_id", null: false
    t.index ["citizen_id"], name: "index_citizen_merges_on_citizen_id"
    t.index ["old_citizen_id"], name: "index_citizen_merges_on_old_citizen_id", unique: true
  end

  create_table "citizen_name_readings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name_text", null: false
    t.string "shape", null: false
    t.string "outcome", null: false
    t.jsonb "parts"
    t.float "probability"
    t.string "pick"
    t.jsonb "candidates", default: [], null: false
    t.string "model", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "reviewed_by"
    t.datetime "queued_at"
    t.uuid "citizen_id", null: false
    t.index ["citizen_id"], name: "index_citizen_name_readings_on_citizen_id", unique: true
    t.index ["outcome"], name: "index_citizen_name_readings_on_outcome"
    t.check_constraint "(outcome::text <> ALL (ARRAY['jev'::character varying, 'settled'::character varying]::text[])) OR parts IS NOT NULL", name: "citizen_name_readings_parts"
    t.check_constraint "outcome::text = ANY (ARRAY['jev'::character varying, 'overflow'::character varying, 'settled'::character varying, 'rejected'::character varying]::text[])", name: "citizen_name_readings_outcome"
  end

  create_table "citizens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "bio"
    t.date "birth_date"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "entity_code"
    t.string "first_name"
    t.string "last_name"
    t.string "middle_name"
    t.datetime "updated_at", null: false
    t.string "username"
    t.string "username_status"
    t.boolean "fictional", default: false, null: false
    t.index ["entity_code"], name: "index_citizens_on_entity_code", unique: true
    t.index ["username"], name: "index_citizens_on_username", unique: true
  end

  create_table "communication_features", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "candidacy_id", null: false
    t.uuid "communication_id", null: false
    t.index ["candidacy_id"], name: "index_communication_features_on_candidacy_id"
    t.index ["communication_id", "candidacy_id"], name: "idx_on_communication_id_candidacy_id_1b61ee98d8", unique: true
    t.index ["communication_id"], name: "index_communication_features_on_communication_id"
  end

  create_table "communications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "archived_url"
    t.string "availability", default: "available", null: false
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.string "entity_code"
    t.string "kind", null: false
    t.string "language"
    t.string "platform_id"
    t.date "published_on", null: false
    t.text "summary"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.uuid "channel_id"
    t.index ["channel_id"], name: "index_communications_on_channel_id"
    t.index ["entity_code"], name: "index_communications_on_entity_code", unique: true
    t.index ["url"], name: "index_communications_on_url", unique: true
  end

  create_table "counties", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "fips"
    t.datetime "created_at", null: false
    t.string "entity_code"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.uuid "state_id", null: false
    t.index ["entity_code"], name: "index_counties_on_entity_code", unique: true
    t.index ["state_id"], name: "index_counties_on_state_id"
  end

  create_table "countries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "entity_code"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["entity_code"], name: "index_countries_on_entity_code", unique: true
  end

  create_table "dimension_rating_revisions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "rated_type", null: false
    t.string "dimension_key", null: false
    t.string "event", null: false
    t.integer "value"
    t.jsonb "definition", null: false
    t.datetime "created_at", null: false
    t.uuid "voter_id", null: false
    t.uuid "rated_id", null: false
    t.index ["rated_type", "rated_id"], name: "index_dimension_rating_revisions_on_rated_type_and_rated_id"
    t.index ["voter_id"], name: "index_dimension_rating_revisions_on_voter_id"
    t.check_constraint "event::text = ANY (ARRAY['rate'::character varying, 'change'::character varying, 'clear'::character varying]::text[])", name: "dimension_rating_revisions_event"
  end

  create_table "dimension_ratings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "rated_type", null: false
    t.string "dimension_key", null: false
    t.integer "dimension_version", null: false
    t.integer "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "voter_id", null: false
    t.uuid "rated_id", null: false
    t.index ["rated_type", "rated_id"], name: "index_dimension_ratings_on_rated"
    t.index ["voter_id", "rated_type", "rated_id", "dimension_key"], name: "index_dimension_ratings_once_per_voter", unique: true
    t.index ["voter_id"], name: "index_dimension_ratings_on_voter_id"
    t.check_constraint "value >= '-100'::integer AND value <= 500", name: "dimension_ratings_value_on_standard_scale"
  end

  create_table "districts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "entity_code"
    t.string "kind", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_code"], name: "index_districts_on_entity_code", unique: true
  end

  create_table "elections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.date "early_voting_ends_on"
    t.date "early_voting_starts_on"
    t.date "election_date", null: false
    t.string "entity_code"
    t.boolean "is_historical"
    t.boolean "is_mock"
    t.string "kind"
    t.string "name", null: false
    t.string "status"
    t.datetime "updated_at", null: false
    t.uuid "jurisdiction_id", null: false
    t.uuid "creator_id"
    t.uuid "year_id", null: false
    t.index ["creator_id"], name: "index_elections_on_creator_id"
    t.index ["entity_code"], name: "index_elections_on_entity_code", unique: true
    t.index ["jurisdiction_id"], name: "index_elections_on_jurisdiction_id"
    t.index ["year_id"], name: "index_elections_on_year_id"
    t.check_constraint "early_voting_starts_on <= early_voting_ends_on", name: "elections_early_voting_dates_ordered"
    t.check_constraint "early_voting_starts_on <= election_date AND early_voting_ends_on <= election_date", name: "elections_early_voting_before_election_date"
  end

  create_table "endorsements", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "endorsed_on"
    t.string "endorser_type", null: false
    t.string "kind", default: "public", null: false
    t.text "notes"
    t.integer "strength"
    t.datetime "updated_at", null: false
    t.date "withdrawn_on"
    t.uuid "candidacy_id", null: false
    t.uuid "ballot_line_id"
    t.uuid "endorser_id", null: false
    t.index ["ballot_line_id"], name: "index_endorsements_on_ballot_line_id", unique: true
    t.index ["candidacy_id", "endorser_type", "endorser_id", "kind"], name: "index_endorsements_on_candidacy_endorser_and_kind", unique: true
    t.index ["candidacy_id"], name: "index_endorsements_on_candidacy_id"
    t.index ["endorser_type", "endorser_id"], name: "index_endorsements_on_endorser"
  end

  create_table "engagements", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "engageable_type", null: false
    t.string "kind", null: false
    t.datetime "updated_at", null: false
    t.uuid "voter_id", null: false
    t.uuid "engageable_id", null: false
    t.index ["engageable_type", "engageable_id", "kind"], name: "index_engagements_on_record_and_kind"
    t.index ["voter_id", "engageable_type", "engageable_id", "kind"], name: "index_engagements_once_per_voter_record_and_kind", unique: true
    t.index ["voter_id"], name: "index_engagements_on_voter_id"
    t.check_constraint "kind::text = ANY (ARRAY['bookmark'::character varying::text, 'favorite'::character varying::text, 'follow'::character varying::text, 'hide'::character varying::text])", name: "engagements_kind_is_known"
  end

  create_table "entity_codes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "canonical_code", null: false
    t.string "catalog", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "namespace", null: false
    t.string "record_type"
    t.datetime "updated_at", null: false
    t.uuid "record_id"
    t.index ["namespace", "catalog", "canonical_code"], name: "index_entity_codes_on_namespace_and_catalog_and_canonical_code"
    t.index ["namespace", "catalog", "code"], name: "index_entity_codes_on_namespace_and_catalog_and_code", unique: true
    t.index ["record_type", "record_id"], name: "index_entity_codes_on_record"
  end

  create_table "governance_types", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "decision_making_process"
    t.text "description"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "governing_bodies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "branch"
    t.datetime "created_at", null: false
    t.text "description"
    t.date "established_date"
    t.boolean "is_active"
    t.string "meeting_schedule"
    t.string "name"
    t.datetime "updated_at", null: false
    t.uuid "governance_type_id", null: false
    t.uuid "jurisdiction_id", null: false
    t.index ["governance_type_id"], name: "index_governing_bodies_on_governance_type_id"
    t.index ["jurisdiction_id"], name: "index_governing_bodies_on_jurisdiction_id"
  end

  create_table "image_placements", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "entity_code"
    t.string "subject_type", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "image_id", null: false
    t.uuid "subject_id", null: false
    t.index ["entity_code"], name: "index_image_placements_on_entity_code", unique: true
    t.index ["image_id"], name: "index_image_placements_on_image_id"
    t.index ["subject_type", "subject_id", "image_id"], name: "idx_on_subject_type_subject_id_image_id_6d95d58e71", unique: true
    t.index ["subject_type", "subject_id"], name: "index_image_placements_on_subject"
    t.check_constraint "\"position\" >= 0", name: "image_placements_position_nonnegative"
  end

  create_table "images", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "entity_code"
    t.string "url"
    t.string "alt_text"
    t.string "credit"
    t.string "source_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_code"], name: "index_images_on_entity_code", unique: true
    t.index ["url"], name: "index_images_on_url", unique: true
  end

  create_table "invites", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "invitee_id", null: false
    t.uuid "inviter_id", null: false
    t.index ["invitee_id"], name: "index_invites_on_invitee_id"
    t.index ["inviter_id", "invitee_id"], name: "index_invites_on_inviter_id_and_invitee_id", unique: true
    t.index ["inviter_id"], name: "index_invites_on_inviter_id"
    t.check_constraint "inviter_id <> invitee_id", name: "invites_cannot_invite_self"
  end

  create_table "issues", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "entity_code"
    t.string "title"
    t.datetime "updated_at", null: false
    t.uuid "topic_id", null: false
    t.index ["entity_code"], name: "index_issues_on_entity_code", unique: true
    t.index ["topic_id"], name: "index_issues_on_topic_id"
  end

  create_table "jurisdiction_boundaries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.geometry "geometry", limit: {srid: 4326, type: "multi_polygon"}, null: false
    t.datetime "updated_at", null: false
    t.date "valid_from", null: false
    t.date "valid_until"
    t.uuid "jurisdiction_id", null: false
    t.index ["geometry"], name: "index_jurisdiction_boundaries_on_geometry", using: :gist
    t.index ["jurisdiction_id"], name: "index_jurisdiction_boundaries_on_jurisdiction_id"
    t.check_constraint "st_isvalid(geometry) AND NOT st_isempty(geometry)", name: "jurisdiction_boundaries_valid_geometry"
    t.check_constraint "valid_until IS NULL OR valid_until > valid_from", name: "jurisdiction_boundaries_valid_dates"
    t.exclusion_constraint "jurisdiction_id WITH =, daterange(valid_from, valid_until, '[)'::text) WITH &&", using: :gist, name: "jurisdiction_boundaries_cannot_overlap_in_time"
  end

  create_table "jurisdictions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "jurisdictionable_type", null: false
    t.datetime "updated_at", null: false
    t.string "census_class"
    t.string "census_geoid"
    t.uuid "parent_id"
    t.uuid "jurisdictionable_id", null: false
    t.index ["census_class", "census_geoid"], name: "index_jurisdictions_on_census_class_and_census_geoid", unique: true, where: "(census_geoid IS NOT NULL)"
    t.index ["jurisdictionable_type", "jurisdictionable_id"], name: "index_jurisdictions_on_jurisdictionable", unique: true
    t.index ["parent_id"], name: "index_jurisdictions_on_parent_id"
    t.check_constraint "(census_class IS NULL) = (census_geoid IS NULL)", name: "jurisdictions_census_ids_together"
    t.check_constraint "parent_id <> id", name: "jurisdictions_cannot_parent_themselves"
  end

  create_table "mountain_drafts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "baseline"
    t.jsonb "ratings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "race_id", null: false
    t.uuid "voter_id", null: false
    t.index ["race_id"], name: "index_mountain_drafts_on_race_id"
    t.index ["voter_id", "race_id"], name: "index_mountain_drafts_on_voter_id_and_race_id", unique: true
    t.check_constraint "baseline >= 0 AND baseline <= 500", name: "mountain_drafts_baseline_in_range"
  end

  create_table "municipalities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "entity_code"
    t.string "name"
    t.datetime "updated_at", null: false
    t.uuid "state_id", null: false
    t.uuid "county_id"
    t.uuid "parent_municipality_id"
    t.index ["county_id"], name: "index_municipalities_on_county_id"
    t.index ["entity_code"], name: "index_municipalities_on_entity_code", unique: true
    t.index ["parent_municipality_id"], name: "index_municipalities_on_parent_municipality_id"
    t.index ["state_id"], name: "index_municipalities_on_state_id"
  end

  create_table "offices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "entity_code"
    t.boolean "is_active"
    t.text "notes"
    t.string "seat_code"
    t.datetime "updated_at", null: false
    t.integer "nominee_count"
    t.uuid "governing_body_id"
    t.uuid "jurisdiction_id", null: false
    t.uuid "chamber_id"
    t.uuid "position_id", null: false
    t.uuid "nominee_for_office_id"
    t.uuid "nominating_organization_id"
    t.index ["chamber_id"], name: "index_offices_on_chamber_id"
    t.index ["entity_code"], name: "index_offices_on_entity_code", unique: true
    t.index ["governing_body_id"], name: "index_offices_on_governing_body_id"
    t.index ["jurisdiction_id"], name: "index_offices_on_jurisdiction_id"
    t.index ["nominating_organization_id"], name: "index_offices_on_nominating_organization_id"
    t.index ["nominee_for_office_id"], name: "index_offices_on_nominee_for_office_id"
    t.index ["position_id"], name: "index_offices_on_position_id"
    t.check_constraint "(nominee_for_office_id IS NULL) = (nominating_organization_id IS NULL) AND (nominee_for_office_id IS NULL) = (nominee_count IS NULL)", name: "nominations_name_their_office_organization_and_count"
  end

  create_table "official_codes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "code_number"
    t.datetime "created_at", null: false
    t.date "effective_date"
    t.text "enforcement_mechanism"
    t.text "full_text"
    t.text "penalty_structure"
    t.string "status"
    t.text "summary"
    t.string "title"
    t.datetime "updated_at", null: false
    t.uuid "policy_id", null: false
    t.index ["policy_id"], name: "index_official_codes_on_policy_id"
  end

  create_table "official_results", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "votes", null: false
    t.decimal "vote_share", precision: 5, scale: 2
    t.boolean "winner", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "candidacy_id", null: false
    t.uuid "race_id", null: false
    t.index ["candidacy_id"], name: "index_official_results_on_candidacy_id"
    t.index ["race_id", "candidacy_id"], name: "index_official_results_on_race_id_and_candidacy_id", unique: true
    t.check_constraint "vote_share >= 0::numeric AND vote_share <= 100::numeric", name: "official_results_vote_share_in_range"
    t.check_constraint "votes >= 0", name: "official_results_votes_not_negative"
  end

  create_table "organizations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "abbreviation"
    t.datetime "created_at", null: false
    t.string "entity_code"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.string "type", default: "Organization", null: false
    t.string "kind"
    t.uuid "state_id"
    t.index ["entity_code"], name: "index_organizations_on_entity_code", unique: true
    t.index ["state_id", "name"], name: "index_organizations_on_state_id_and_name", unique: true
    t.index ["state_id"], name: "index_organizations_on_state_id"
    t.check_constraint "type::text <> 'Party'::text OR state_id IS NOT NULL", name: "parties_have_a_state"
  end

  create_table "policies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.date "enacted_date"
    t.date "expiration_date"
    t.string "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.uuid "area_of_concern_id", null: false
    t.uuid "governing_body_id", null: false
    t.uuid "approach_id", null: false
    t.index ["approach_id"], name: "index_policies_on_approach_id"
    t.index ["area_of_concern_id"], name: "index_policies_on_area_of_concern_id"
    t.index ["governing_body_id"], name: "index_policies_on_governing_body_id"
  end

  create_table "positions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "branch"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "entity_code"
    t.integer "term_length_years"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["entity_code"], name: "index_positions_on_entity_code", unique: true
  end

  create_table "public_mountains", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "snapshot", null: false
    t.binary "preview_png", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "voter_id", null: false
    t.uuid "race_id", null: false
    t.index ["race_id"], name: "index_public_mountains_on_race_id"
    t.index ["voter_id", "race_id"], name: "index_public_mountains_on_voter_id_and_race_id", unique: true
    t.index ["voter_id"], name: "index_public_mountains_on_voter_id"
  end

  create_table "races", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "certification_status"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "entity_code"
    t.string "status", default: "upcoming", null: false
    t.datetime "updated_at", null: false
    t.string "decided_by"
    t.uuid "office_id", null: false
    t.uuid "election_id", null: false
    t.index ["election_id"], name: "index_races_on_election_id"
    t.index ["entity_code"], name: "index_races_on_entity_code", unique: true
    t.index ["office_id"], name: "index_races_on_office_id"
  end

  create_table "rating_archives", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.integer "rating"
    t.string "reason"
    t.datetime "updated_at", null: false
    t.uuid "voter_id", null: false
    t.uuid "candidacy_id", null: false
    t.index ["candidacy_id"], name: "index_rating_archives_on_candidacy_id"
    t.index ["voter_id"], name: "index_rating_archives_on_voter_id"
  end

  create_table "ratings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "rating"
    t.datetime "updated_at", null: false
    t.uuid "voter_id", null: false
    t.uuid "candidacy_id", null: false
    t.index ["candidacy_id"], name: "index_ratings_on_candidacy_id"
    t.index ["voter_id"], name: "index_ratings_on_voter_id"
  end

  create_table "residences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "notes"
    t.datetime "registered_at"
    t.string "status"
    t.datetime "updated_at", null: false
    t.date "started_on", null: false
    t.date "ended_on"
    t.uuid "voter_id", null: false
    t.uuid "state_house_district_id"
    t.uuid "congressional_district_id"
    t.uuid "state_senate_district_id"
    t.uuid "jurisdiction_id", null: false
    t.uuid "county_id"
    t.index ["congressional_district_id"], name: "index_residences_on_congressional_district_id"
    t.index ["county_id"], name: "index_residences_on_county_id"
    t.index ["jurisdiction_id"], name: "index_residences_on_jurisdiction_id"
    t.index ["state_house_district_id"], name: "index_residences_on_state_house_district_id"
    t.index ["state_senate_district_id"], name: "index_residences_on_state_senate_district_id"
    t.index ["voter_id"], name: "index_residences_on_voter_id"
    t.check_constraint "ended_on IS NULL OR ended_on >= started_on", name: "residences_end_after_start"
  end

  create_table "rizz_backchannel_logout_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "jti", null: false
    t.string "rizz_sub", null: false
    t.bigint "rizz_epoch", null: false
    t.datetime "processed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["jti"], name: "index_rizz_backchannel_logout_events_on_jti", unique: true
    t.index ["rizz_sub"], name: "index_rizz_backchannel_logout_events_on_rizz_sub"
  end

  create_table "rizz_claim_handoffs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "handoff_jti", null: false
    t.string "operation_id", null: false
    t.string "speaker_label", null: false
    t.string "callback_uri", null: false
    t.string "browser_token_digest", null: false
    t.string "intent", default: "claim", null: false
    t.string "email"
    t.string "first_name"
    t.string "last_name"
    t.string "display_name"
    t.string "username"
    t.string "suggested_username"
    t.string "encrypted_password"
    t.string "google_uid"
    t.uuid "verified_voter_id"
    t.datetime "verified_at"
    t.datetime "expires_at", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_rizz_claim_handoffs_on_expires_at"
    t.index ["handoff_jti"], name: "index_rizz_claim_handoffs_on_handoff_jti", unique: true
    t.index ["operation_id"], name: "index_rizz_claim_handoffs_on_operation_id"
    t.index ["verified_voter_id"], name: "index_rizz_claim_handoffs_on_verified_voter_id"
    t.check_constraint "intent::text = ANY (ARRAY['claim'::character varying, 'create'::character varying]::text[])", name: "rizz_claim_handoffs_intent"
  end

  create_table "rizz_claim_receipts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "voter_id"
    t.uuid "rizz_claim_handoff_id"
    t.string "operation_id", null: false
    t.string "receipt_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_rizz_claim_receipts_on_expires_at"
    t.index ["operation_id"], name: "index_rizz_claim_receipts_on_operation_id", unique: true
    t.index ["receipt_digest"], name: "index_rizz_claim_receipts_on_receipt_digest", unique: true
    t.index ["rizz_claim_handoff_id"], name: "index_rizz_claim_receipts_on_rizz_claim_handoff_id"
    t.index ["voter_id"], name: "index_rizz_claim_receipts_on_voter_id"
    t.check_constraint "voter_id IS NOT NULL AND rizz_claim_handoff_id IS NULL OR voter_id IS NULL AND rizz_claim_handoff_id IS NOT NULL", name: "rizz_claim_receipts_subject"
  end

  create_table "rizz_feed_cursors", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "purpose", null: false
    t.string "cursor"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["purpose"], name: "index_rizz_feed_cursors_on_purpose", unique: true
  end

  create_table "rizz_names", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "purpose", null: false
    t.string "state", default: "current", null: false
    t.uuid "rizz_entity_id"
    t.string "rizz_code"
    t.string "display_name"
    t.jsonb "display_parts"
    t.string "sort_key"
    t.text "name_sort", array: true
    t.jsonb "search_forms", default: [], null: false
    t.uuid "form_id"
    t.uuid "rule_id"
    t.string "view_version"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "citizen_id", null: false
    t.index ["citizen_id", "purpose"], name: "index_rizz_names_on_citizen_id_and_purpose", unique: true
    t.index ["purpose", "rizz_entity_id"], name: "index_rizz_names_on_purpose_and_rizz_entity_id"
    t.check_constraint "state::text = ANY (ARRAY['current'::character varying, 'invalidated'::character varying]::text[])", name: "rizz_names_state"
  end

  create_table "rizz_syncs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "state", default: "pending", null: false
    t.uuid "rizz_entity_id"
    t.integer "rizz_version"
    t.string "rizz_code"
    t.string "source_revision"
    t.uuid "review_id"
    t.string "last_error"
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "citizen_id", null: false
    t.index ["citizen_id"], name: "index_rizz_syncs_on_citizen_id", unique: true
    t.index ["rizz_entity_id"], name: "index_rizz_syncs_on_rizz_entity_id"
    t.index ["state"], name: "index_rizz_syncs_on_state"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying, 'synced'::character varying, 'review'::character varying, 'merge_needed'::character varying, 'failed'::character varying, 'skipped'::character varying, 'held'::character varying]::text[])", name: "rizz_syncs_state"
  end

  create_table "rule_conditions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "kind", default: 0, null: false
    t.string "label", null: false
    t.text "notes"
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.uuid "statement_id", null: false
    t.index ["statement_id", "slug"], name: "index_rule_conditions_on_statement_id_and_slug", unique: true
    t.index ["statement_id"], name: "index_rule_conditions_on_statement_id"
  end

  create_table "rule_source_links", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "linkable_type", null: false
    t.bigint "lu_unit_id", null: false
    t.text "notes"
    t.integer "relationship_kind", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "linkable_id", null: false
    t.index ["linkable_type", "linkable_id"], name: "index_rule_source_links_on_linkable"
    t.index ["lu_unit_id"], name: "index_rule_source_links_on_lu_unit_id"
  end

  create_table "rule_statements", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action_label"
    t.string "actor_label"
    t.datetime "created_at", null: false
    t.integer "effect", default: 0, null: false
    t.string "object_label"
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.text "summary", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.uuid "topic_id", null: false
    t.index ["topic_id", "slug"], name: "index_rule_statements_on_topic_id_and_slug", unique: true
    t.index ["topic_id"], name: "index_rule_statements_on_topic_id"
  end

  create_table "rule_topics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_rule_topics_on_slug", unique: true
  end

  create_table "stance_evidences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "entity_code"
    t.integer "offset_seconds"
    t.text "quote"
    t.string "relation", default: "states", null: false
    t.datetime "updated_at", null: false
    t.uuid "stance_id", null: false
    t.uuid "communication_id", null: false
    t.index ["communication_id"], name: "index_stance_evidences_on_communication_id"
    t.index ["entity_code"], name: "index_stance_evidences_on_entity_code", unique: true
    t.index ["stance_id", "communication_id"], name: "index_stance_evidences_on_stance_id_and_communication_id", unique: true
    t.index ["stance_id"], name: "index_stance_evidences_on_stance_id"
  end

  create_table "stances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "entity_code"
    t.text "evidence_links"
    t.text "explanation"
    t.string "priority_level"
    t.datetime "updated_at", null: false
    t.uuid "candidacy_id", null: false
    t.uuid "approach_id", null: false
    t.index ["approach_id"], name: "index_stances_on_approach_id"
    t.index ["candidacy_id", "approach_id"], name: "index_stances_on_candidacy_id_and_approach_id", unique: true
    t.index ["candidacy_id"], name: "index_stances_on_candidacy_id"
    t.index ["entity_code"], name: "index_stances_on_entity_code", unique: true
  end

  create_table "states", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.string "entity_code"
    t.string "name"
    t.datetime "updated_at", null: false
    t.uuid "country_id", null: false
    t.index ["country_id"], name: "index_states_on_country_id"
    t.index ["entity_code"], name: "index_states_on_entity_code", unique: true
  end

  create_table "topics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "entity_code"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["entity_code"], name: "index_topics_on_entity_code", unique: true
  end

  create_table "voter_links", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "label", null: false
    t.string "url", null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "voter_id", null: false
    t.index ["voter_id", "position", "id"], name: "index_voter_links_on_voter_id_and_position_and_id"
  end

  create_table "voter_race_baseline_archives", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "archived_at", null: false
    t.integer "baseline", null: false
    t.datetime "created_at", null: false
    t.integer "new_baseline"
    t.integer "previous_baseline"
    t.string "reason", null: false
    t.datetime "updated_at", null: false
    t.uuid "race_id", null: false
    t.uuid "voter_id", null: false
    t.index ["archived_at"], name: "index_voter_race_baseline_archives_on_archived_at"
    t.index ["race_id"], name: "index_voter_race_baseline_archives_on_race_id"
    t.index ["voter_id", "race_id"], name: "index_baseline_archives_on_voter_and_race"
    t.index ["voter_id"], name: "index_voter_race_baseline_archives_on_voter_id"
  end

  create_table "voter_race_baselines", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "baseline"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "counted_as", default: "visitor", null: false
    t.uuid "voter_id", null: false
    t.uuid "race_id", null: false
    t.index ["race_id", "counted_as"], name: "index_voter_race_baselines_on_race_id_and_counted_as"
    t.index ["race_id"], name: "index_voter_race_baselines_on_race_id"
    t.index ["voter_id", "race_id"], name: "index_voter_race_baselines_on_voter_and_race", unique: true
    t.index ["voter_id"], name: "index_voter_race_baselines_on_voter_id"
    t.check_constraint "counted_as::text = ANY (ARRAY['resident'::character varying::text, 'visitor'::character varying::text])", name: "voter_race_baselines_counted_as_is_known"
  end

  create_table "voter_race_preferences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "include_primary_candidates", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "voter_id", null: false
    t.uuid "race_id", null: false
    t.index ["race_id"], name: "index_voter_race_preferences_on_race_id"
    t.index ["voter_id", "race_id"], name: "index_voter_race_preferences_on_voter_id_and_race_id", unique: true
  end

  create_table "voter_rizz_bindings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "voter_id", null: false
    t.string "rizz_sub", null: false
    t.string "operation_id", null: false
    t.string "status", default: "active", null: false
    t.bigint "rizz_session_epoch", default: 1, null: false
    t.datetime "connected_at", null: false
    t.datetime "disconnected_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operation_id"], name: "index_voter_rizz_bindings_on_operation_id", unique: true
    t.index ["rizz_sub"], name: "index_voter_rizz_bindings_on_rizz_sub", unique: true
    t.index ["voter_id"], name: "index_voter_rizz_bindings_on_voter_id"
    t.index ["voter_id"], name: "index_voter_rizz_bindings_one_active_per_voter", unique: true, where: "((status)::text = 'active'::text)"
    t.check_constraint "rizz_session_epoch > 0", name: "voter_rizz_bindings_epoch_positive"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'disconnected'::character varying]::text[])", name: "voter_rizz_bindings_status"
  end

  create_table "voter_statements", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "body", null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "voter_id", null: false
    t.index ["voter_id", "position", "id"], name: "index_voter_statements_on_voter_id_and_position_and_id"
  end

  create_table "voters", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "birth_date"
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name"
    t.boolean "is_verified"
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.string "unconfirmed_email"
    t.datetime "updated_at", null: false
    t.string "provider"
    t.string "uid"
    t.string "invite_token", null: false
    t.boolean "public_influencer", default: false, null: false
    t.string "role"
    t.boolean "profile_hidden", default: false, null: false
    t.string "username"
    t.string "display_name"
    t.index "lower((username)::text)", name: "index_voters_on_lower_username", unique: true, where: "(username IS NOT NULL)"
    t.index ["email"], name: "index_voters_on_email", unique: true
    t.index ["invite_token"], name: "index_voters_on_invite_token", unique: true
    t.index ["profile_hidden"], name: "index_voters_on_profile_hidden"
    t.index ["provider", "uid"], name: "index_voters_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_voters_on_reset_password_token", unique: true
    t.index ["role"], name: "index_voters_on_role"
  end

  create_table "years", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "is_even_year"
    t.boolean "is_presidential_year"
    t.datetime "updated_at", null: false
    t.integer "year"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "approaches", "issues"
  add_foreign_key "ballot_lines", "candidacies"
  add_foreign_key "ballot_lines", "organizations", column: "party_id"
  add_foreign_key "candidacies", "candidacies", column: "primary_candidacy_id"
  add_foreign_key "candidacies", "citizens"
  add_foreign_key "candidacies", "races"
  add_foreign_key "candidacy_merges", "candidacies", on_delete: :restrict
  add_foreign_key "chambers", "governing_bodies"
  add_foreign_key "channels", "voters", column: "reviewed_by_id"
  add_foreign_key "citizen_merges", "citizens", on_delete: :restrict
  add_foreign_key "citizen_name_readings", "citizens", on_delete: :cascade
  add_foreign_key "communication_features", "candidacies"
  add_foreign_key "communication_features", "communications"
  add_foreign_key "communications", "channels"
  add_foreign_key "counties", "states"
  add_foreign_key "dimension_rating_revisions", "voters"
  add_foreign_key "dimension_ratings", "voters"
  add_foreign_key "elections", "jurisdictions"
  add_foreign_key "elections", "voters", column: "creator_id", on_delete: :nullify
  add_foreign_key "elections", "years"
  add_foreign_key "endorsements", "ballot_lines"
  add_foreign_key "endorsements", "candidacies"
  add_foreign_key "engagements", "voters"
  add_foreign_key "governing_bodies", "governance_types"
  add_foreign_key "governing_bodies", "jurisdictions"
  add_foreign_key "image_placements", "images"
  add_foreign_key "invites", "voters", column: "invitee_id", on_delete: :cascade
  add_foreign_key "invites", "voters", column: "inviter_id", on_delete: :cascade
  add_foreign_key "issues", "topics"
  add_foreign_key "jurisdiction_boundaries", "jurisdictions"
  add_foreign_key "jurisdictions", "jurisdictions", column: "parent_id"
  add_foreign_key "mountain_drafts", "races", on_delete: :cascade
  add_foreign_key "mountain_drafts", "voters", on_delete: :cascade
  add_foreign_key "municipalities", "counties"
  add_foreign_key "municipalities", "municipalities", column: "parent_municipality_id"
  add_foreign_key "municipalities", "states"
  add_foreign_key "offices", "chambers"
  add_foreign_key "offices", "governing_bodies"
  add_foreign_key "offices", "jurisdictions"
  add_foreign_key "offices", "offices", column: "nominee_for_office_id"
  add_foreign_key "offices", "organizations", column: "nominating_organization_id"
  add_foreign_key "offices", "positions"
  add_foreign_key "official_codes", "policies"
  add_foreign_key "official_results", "candidacies", on_delete: :cascade
  add_foreign_key "official_results", "races", on_delete: :cascade
  add_foreign_key "organizations", "states"
  add_foreign_key "policies", "approaches"
  add_foreign_key "policies", "area_of_concerns"
  add_foreign_key "policies", "governing_bodies"
  add_foreign_key "public_mountains", "races"
  add_foreign_key "public_mountains", "voters"
  add_foreign_key "races", "elections"
  add_foreign_key "races", "offices"
  add_foreign_key "rating_archives", "candidacies"
  add_foreign_key "rating_archives", "voters"
  add_foreign_key "ratings", "candidacies"
  add_foreign_key "ratings", "voters"
  add_foreign_key "residences", "jurisdictions"
  add_foreign_key "residences", "jurisdictions", column: "congressional_district_id"
  add_foreign_key "residences", "jurisdictions", column: "county_id"
  add_foreign_key "residences", "jurisdictions", column: "state_house_district_id"
  add_foreign_key "residences", "jurisdictions", column: "state_senate_district_id"
  add_foreign_key "residences", "voters"
  add_foreign_key "rizz_claim_handoffs", "voters", column: "verified_voter_id", on_delete: :nullify
  add_foreign_key "rizz_claim_receipts", "rizz_claim_handoffs", on_delete: :cascade
  add_foreign_key "rizz_claim_receipts", "voters", on_delete: :cascade
  add_foreign_key "rizz_names", "citizens", on_delete: :cascade
  add_foreign_key "rizz_syncs", "citizens", on_delete: :cascade
  add_foreign_key "rule_conditions", "rule_statements", column: "statement_id"
  add_foreign_key "rule_statements", "rule_topics", column: "topic_id"
  add_foreign_key "stance_evidences", "communications"
  add_foreign_key "stance_evidences", "stances"
  add_foreign_key "stances", "approaches"
  add_foreign_key "stances", "candidacies"
  add_foreign_key "states", "countries"
  add_foreign_key "voter_links", "voters", on_delete: :cascade
  add_foreign_key "voter_race_baseline_archives", "races"
  add_foreign_key "voter_race_baseline_archives", "voters"
  add_foreign_key "voter_race_baselines", "races"
  add_foreign_key "voter_race_baselines", "voters"
  add_foreign_key "voter_race_preferences", "races", on_delete: :cascade
  add_foreign_key "voter_race_preferences", "voters", on_delete: :cascade
  add_foreign_key "voter_rizz_bindings", "voters", on_delete: :cascade
  add_foreign_key "voter_statements", "voters", on_delete: :cascade

  create_view "mountain_ratings", sql_definition: <<-SQL
      SELECT ratings.id,
      ratings.voter_id,
      ratings.candidacy_id,
      candidacies.race_id,
      ratings.rating,
      voter_race_baselines.baseline,
      voter_race_baselines.counted_as,
      (candidacies.primary_candidacy_id IS NOT NULL) AS from_primary,
      (ratings.rating > voter_race_baselines.baseline) AS approved
     FROM (((ratings
       JOIN candidacies ON ((candidacies.id = ratings.candidacy_id)))
       JOIN voter_race_baselines ON (((voter_race_baselines.voter_id = ratings.voter_id) AND (voter_race_baselines.race_id = candidacies.race_id))))
       LEFT JOIN voter_race_preferences ON (((voter_race_preferences.voter_id = ratings.voter_id) AND (voter_race_preferences.race_id = candidacies.race_id))))
    WHERE ((candidacies.primary_candidacy_id IS NULL) OR voter_race_preferences.include_primary_candidates);
  SQL
end

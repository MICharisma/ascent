# frozen_string_literal: true

class CreateRizzSignInTables < ActiveRecord::Migration[8.1]
  def change
    create_table :voter_rizz_bindings, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :voter, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :rizz_sub, null: false
      t.string :operation_id, null: false
      t.string :status, null: false, default: "active"
      t.bigint :rizz_session_epoch, null: false, default: 1
      t.datetime :connected_at, null: false
      t.datetime :disconnected_at
      t.timestamps

      t.index :rizz_sub, unique: true
      t.index :operation_id, unique: true
      t.index :voter_id, unique: true, where: "status = 'active'", name: "index_voter_rizz_bindings_one_active_per_voter"
      t.check_constraint "status IN ('active', 'disconnected')", name: "voter_rizz_bindings_status"
      t.check_constraint "rizz_session_epoch > 0", name: "voter_rizz_bindings_epoch_positive"
    end

    create_table :rizz_claim_handoffs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :handoff_jti, null: false
      t.string :operation_id, null: false
      t.string :speaker_label, null: false
      t.string :callback_uri, null: false
      t.string :browser_token_digest, null: false
      t.string :intent, null: false, default: "claim"
      t.string :email
      t.string :first_name
      t.string :last_name
      t.string :display_name
      t.string :username
      t.string :suggested_username
      t.string :encrypted_password
      t.string :google_uid
      t.references :verified_voter, type: :uuid, foreign_key: { to_table: :voters, on_delete: :nullify }
      t.datetime :verified_at
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps

      t.index :handoff_jti, unique: true
      t.index :operation_id
      t.index :expires_at
      t.check_constraint "intent IN ('claim', 'create')", name: "rizz_claim_handoffs_intent"
    end

    create_table :rizz_claim_receipts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :voter, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :rizz_claim_handoff, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :operation_id, null: false
      t.string :receipt_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps

      t.index :operation_id, unique: true
      t.index :receipt_digest, unique: true
      t.index :expires_at
      t.check_constraint "(voter_id IS NOT NULL AND rizz_claim_handoff_id IS NULL) OR (voter_id IS NULL AND rizz_claim_handoff_id IS NOT NULL)",
        name: "rizz_claim_receipts_subject"
    end

    create_table :rizz_backchannel_logout_events, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :jti, null: false
      t.string :rizz_sub, null: false
      t.bigint :rizz_epoch, null: false
      t.datetime :processed_at, null: false
      t.timestamps

      t.index :jti, unique: true
      t.index :rizz_sub
    end
  end
end

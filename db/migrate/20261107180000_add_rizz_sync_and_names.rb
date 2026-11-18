# Ascent's link to Rizz, the shared naming and identity service.
#
# rizz_syncs records each Citizen's standing with Rizz: whether its names were
# sent, which Rizz entity holds it, and any identity review Rizz is holding.
#
# rizz_names holds the name Rizz authorizes Ascent to show for each Citizen,
# kept apart from the Citizen's own name columns. Those columns are what
# Ascent sends to Rizz, and the ballot spelling Ascent records; a Rizz label
# written into them would go back to Rizz as Ascent's own source data.
# name_sort is what Ascent sorts the name by, worked out from display_parts.
# rizz_feed_cursors records how far Ascent has read Rizz's event feed.
class AddRizzSyncAndNames < ActiveRecord::Migration[8.1]
  def change
    create_table :rizz_syncs do |t|
      t.references :citizen, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :state, null: false, default: "pending"
      t.uuid :rizz_entity_id
      t.integer :rizz_version
      t.string :rizz_code
      t.string :source_revision
      t.uuid :review_id
      t.string :last_error
      t.datetime :synced_at
      t.timestamps
    end
    add_index :rizz_syncs, :rizz_entity_id
    add_index :rizz_syncs, :state
    add_check_constraint :rizz_syncs, "state IN ('pending', 'synced', 'review', 'merge_needed', 'failed', 'skipped')", name: "rizz_syncs_state"

    create_table :rizz_names do |t|
      t.references :citizen, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :purpose, null: false
      t.string :state, null: false, default: "current"
      t.uuid :rizz_entity_id
      t.string :rizz_code
      t.string :display_name
      t.jsonb :display_parts
      t.string :sort_key
      t.text :name_sort, array: true
      t.jsonb :search_forms, null: false, default: []
      t.uuid :form_id
      t.uuid :rule_id
      t.string :view_version
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :rizz_names, [ :citizen_id, :purpose ], unique: true
    add_index :rizz_names, [ :purpose, :rizz_entity_id ]
    add_check_constraint :rizz_names, "state IN ('current', 'invalidated')", name: "rizz_names_state"

    create_table :rizz_feed_cursors do |t|
      t.string :purpose, null: false, index: { unique: true }
      t.string :cursor
      t.timestamps
    end
  end
end

# Ascent's own reading of each Citizen name whose columns Rizz can't read on
# its own (Rizz::Ascent::NameReader): Jev's pick among the readings code
# proposed, with its probability. A name read with confidence goes to Rizz
# with these parts; any other waits for triage, and its sync is held.
# name_text is the name the reading is for, so a renamed citizen is read again.
class AddCitizenNameReadings < ActiveRecord::Migration[8.1]
  OLD_STATES = "state IN ('pending', 'synced', 'review', 'merge_needed', 'failed', 'skipped')".freeze
  NEW_STATES = "state IN ('pending', 'synced', 'review', 'merge_needed', 'failed', 'skipped', 'held')".freeze

  def change
    create_table :citizen_name_readings do |t|
      t.references :citizen, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :name_text, null: false
      t.string :shape, null: false
      t.string :outcome, null: false
      t.jsonb :parts
      t.float :probability
      t.string :pick
      t.jsonb :candidates, null: false, default: []
      t.string :model, null: false
      t.timestamps
    end
    add_index :citizen_name_readings, :outcome
    add_check_constraint :citizen_name_readings, "outcome IN ('jev', 'overflow')", name: "citizen_name_readings_outcome"
    add_check_constraint :citizen_name_readings, "outcome <> 'jev' OR parts IS NOT NULL", name: "citizen_name_readings_parts"

    remove_check_constraint :rizz_syncs, OLD_STATES, name: "rizz_syncs_state"
    add_check_constraint :rizz_syncs, NEW_STATES, name: "rizz_syncs_state"
  end
end

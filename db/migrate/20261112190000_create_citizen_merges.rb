class CreateCitizenMerges < ActiveRecord::Migration[8.1]
  def change
    create_table :citizen_merges do |t|
      t.bigint :old_citizen_id, null: false
      t.references :citizen, null: false, foreign_key: { on_delete: :restrict }
      t.string :rizz_entity_id, null: false
      t.string :performed_by, null: false
      t.jsonb :snapshot, null: false
      t.timestamps
    end
    add_index :citizen_merges, :old_citizen_id, unique: true
  end
end

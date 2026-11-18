class CreateCandidacyMerges < ActiveRecord::Migration[8.1]
  def change
    create_table :candidacy_merges do |t|
      t.bigint :old_candidacy_id, null: false
      t.references :candidacy, null: false, foreign_key: { on_delete: :restrict }
      t.string :performed_by, null: false
      t.jsonb :snapshot, null: false
      t.timestamps
    end
    add_index :candidacy_merges, :old_candidacy_id, unique: true
  end
end

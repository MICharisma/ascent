class CreateDimensionRatings < ActiveRecord::Migration[8.1]
  def change
    create_table :dimension_ratings do |t|
      t.references :voter, null: false, foreign_key: true
      t.references :rated, polymorphic: true, null: false
      t.string :dimension_key, null: false
      t.integer :dimension_version, null: false
      t.integer :value, null: false
      t.timestamps
    end
    add_index :dimension_ratings, %i[voter_id rated_type rated_id dimension_key], unique: true, name: "index_dimension_ratings_once_per_voter"
    add_check_constraint :dimension_ratings, "value BETWEEN -100 AND 500", name: "dimension_ratings_value_on_standard_scale"

    create_table :dimension_rating_revisions do |t|
      t.references :voter, null: false, foreign_key: true
      t.string :rated_type, null: false
      t.bigint :rated_id, null: false
      t.string :dimension_key, null: false
      t.string :event, null: false
      t.integer :value
      t.jsonb :definition, null: false
      t.datetime :created_at, null: false
    end
    add_index :dimension_rating_revisions, %i[rated_type rated_id]
    add_check_constraint :dimension_rating_revisions, "event IN ('rate', 'change', 'clear')", name: "dimension_rating_revisions_event"
  end
end

class RenamePeopleToCitizens < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :candidacies, :people

    rename_table :people, :citizens
    rename_column :candidacies, :person_id, :citizen_id
    rename_index :candidacies, :index_candidacies_from_primaries_once_per_race_and_person,
      :index_candidacies_from_primaries_once_per_race_and_citizen

    add_foreign_key :candidacies, :citizens
  end
end

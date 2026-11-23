# frozen_string_literal: true

class ConvertEngagementsToPolymorphicActor < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :engagements, :voters
    remove_index :engagements, name: "index_engagements_once_per_voter_record_and_kind"
    remove_index :engagements, name: "index_engagements_on_voter_id"

    rename_column :engagements, :voter_id, :actor_id
    add_column :engagements, :actor_type, :string, null: false, default: "Voter"
    change_column_default :engagements, :actor_type, from: "Voter", to: nil

    add_index :engagements, %i[actor_type actor_id engageable_type engageable_id kind],
      unique: true, name: "index_engagements_once_per_actor_record_and_kind"
    add_index :engagements, %i[actor_type actor_id], name: "index_engagements_on_actor"
  end
end

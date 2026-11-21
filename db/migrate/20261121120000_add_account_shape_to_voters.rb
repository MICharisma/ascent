# frozen_string_literal: true

class AddAccountShapeToVoters < ActiveRecord::Migration[8.1]
  def change
    add_column :voters, :username, :string
    add_column :voters, :display_name, :string
    add_index :voters, "lower(username)", unique: true, where: "username IS NOT NULL", name: "index_voters_on_lower_username"
  end
end

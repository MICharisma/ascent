class ConvertStoredPersonTypes < ActiveRecord::Migration[8.1]
  TYPE_COLUMNS = {
    active_storage_attachments: :record_type,
    channels: :owner_type,
    endorsements: :endorser_type,
    engagements: :engageable_type,
    entity_codes: :record_type,
    image_placements: :subject_type,
    jurisdictions: :jurisdictionable_type,
    rule_source_links: :linkable_type
  }.freeze

  def up
    convert_types "Person", "Citizen"
  end

  def down
    convert_types "Citizen", "Person"
  end

  private

  def convert_types(from, to)
    TYPE_COLUMNS.each do |table, column|
      execute <<~SQL
        UPDATE #{table}
        SET #{column} = #{connection.quote(to)}
        WHERE #{column} = #{connection.quote(from)}
      SQL
    end
  end
end

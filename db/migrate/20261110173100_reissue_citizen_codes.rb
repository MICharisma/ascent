class ReissueCitizenCodes < ActiveRecord::Migration[8.1]
  def up
    change_codes <<~SQL
      SELECT id,
        'CITIZEN-' || substring(entity_code FROM 8) AS new_code
      FROM citizens WHERE entity_code LIKE 'PERSON-%'
    SQL
  end

  def down
    change_codes <<~SQL
      SELECT citizen.id,
        'PERSON-' || substring(citizen.entity_code FROM 9) AS new_code
      FROM citizens citizen
      WHERE citizen.entity_code LIKE 'CITIZEN-%'
        AND EXISTS (
          SELECT 1 FROM entity_codes legacy
          WHERE legacy.namespace = 'MIC' AND legacy.catalog = 'ASC'
            AND legacy.code = 'PERSON-' || substring(citizen.entity_code FROM 9)
            AND legacy.record_type = 'Citizen' AND legacy.record_id = citizen.id
        )
    SQL
  end

  private

  def change_codes(changes)
    collisions = connection.select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM (#{changes}) change
      JOIN entity_codes existing ON existing.namespace = 'MIC' AND existing.catalog = 'ASC'
        AND existing.code = change.new_code
      WHERE existing.record_type IS DISTINCT FROM 'Citizen'
        OR existing.record_id IS DISTINCT FROM change.id
    SQL
    raise "Citizen code conversion would claim #{collisions} existing codes" if collisions.positive?

    execute <<~SQL
      INSERT INTO entity_codes
        (namespace, catalog, code, canonical_code, record_type, record_id, created_at, updated_at)
      SELECT 'MIC', 'ASC', new_code, new_code, 'Citizen', id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM (#{changes}) change
      ON CONFLICT (namespace, catalog, code) DO NOTHING
    SQL
    execute <<~SQL
      UPDATE entity_codes issued SET canonical_code = change.new_code
      FROM (#{changes}) change
      WHERE issued.namespace = 'MIC' AND issued.catalog = 'ASC'
        AND issued.record_type = 'Citizen' AND issued.record_id = change.id
    SQL
    execute <<~SQL
      UPDATE citizens citizen SET entity_code = change.new_code
      FROM (#{changes}) change WHERE citizen.id = change.id
    SQL
  end
end

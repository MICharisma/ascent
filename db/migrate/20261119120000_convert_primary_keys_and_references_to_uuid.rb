# frozen_string_literal: true

require "securerandom"

# Converts all application primary keys, foreign keys, unconstrained references,
# polymorphic *_id columns, and mountain_drafts JSONB candidacy keys from bigint
# to uuid while preserving existing rows, relationships, views, and constraints.
#
# Historical deleted-record redirect columns (citizen_merges.old_citizen_id and
# candidacy_merges.old_candidacy_id) are widened from bigint to string so they
# preserve pre-migration integer IDs while recording post-migration UUIDs.
#
# Solid Queue / Solid Cache / Solid Cable tables and PostGIS spatial_ref_sys are
# excluded. Non-reference bigint columns (active_storage_blobs.byte_size and
# rule_source_links.lu_unit_id) remain bigint.
class ConvertPrimaryKeysAndReferencesToUuid < ActiveRecord::Migration[8.1]
  EXCLUDED_TABLES = %w[schema_migrations ar_internal_metadata spatial_ref_sys].freeze
  EXCLUDED_TABLE_PREFIXES = %w[solid_queue_ solid_cache_ solid_cable_].freeze

  UNCONSTRAINED_REFERENCES = [
    %w[ahoy_events visit_id ahoy_visits],
    %w[ahoy_events user_id voters],
    %w[ahoy_visits user_id voters]
  ].freeze

  POLYMORPHIC_COLUMNS = [
    %w[active_storage_attachments record_type record_id],
    %w[channels owner_type owner_id],
    %w[dimension_ratings rated_type rated_id],
    %w[dimension_rating_revisions rated_type rated_id],
    %w[endorsements endorser_type endorser_id],
    %w[engagements engageable_type engageable_id],
    %w[entity_codes record_type record_id],
    %w[image_placements subject_type subject_id],
    %w[jurisdictions jurisdictionable_type jurisdictionable_id],
    %w[rule_source_links linkable_type linkable_id]
  ].freeze

  HISTORICAL_ID_COLUMNS = [
    %w[citizen_merges old_citizen_id],
    %w[candidacy_merges old_candidacy_id]
  ].freeze

  BATCH_SIZE = 1_000

  def up
    tables = target_tables
    return if tables.empty?

    foreign_keys = tables.flat_map { |table| connection.foreign_keys(table) }
      .select { |fk| tables.include?(fk.to_table) }

    fk_pairs = foreign_keys.map { |fk| [ fk.from_table, fk.column ] }.to_set
    unconstrained_refs = UNCONSTRAINED_REFERENCES.select do |from_table, col, to_table|
      tables.include?(from_table) &&
        tables.include?(to_table) &&
        !fk_pairs.include?([ from_table, col ]) &&
        integer_column?(from_table, col)
    end

    polymorphics = POLYMORPHIC_COLUMNS.select do |table, _type_col, id_col|
      tables.include?(table) && integer_column?(table, id_col)
    end

    historical_ids = HISTORICAL_ID_COLUMNS.select do |table, col|
      tables.include?(table) && integer_column?(table, col)
    end

    converted_columns = build_converted_columns(tables, foreign_keys, unconstrained_refs, polymorphics)
    saved_views = capture_dependent_views(tables)
    saved_exclusions = capture_exclusion_constraints(tables, converted_columns)
    saved_indexes = capture_indexes(tables, converted_columns, saved_exclusions)
    saved_checks = capture_check_constraints(tables, converted_columns)
    column_nulls = capture_nullability(tables, foreign_keys, unconstrained_refs, polymorphics)

    # 1. Add uuid_id to every table and backfill time-ordered UUIDv7s.
    tables.each do |table|
      add_column table, :uuid_id, :uuid
      backfill_table_uuids(table)
      change_column_null table, :uuid_id, false
      change_column_default table, :uuid_id, from: nil, to: -> { "gen_random_uuid()" }
    end

    # 2. Add temporary uuid FK columns and backfill from parent uuid_ids.
    foreign_keys.each do |fk|
      tmp_col = temp_uuid_column(fk.column)
      add_column fk.from_table, tmp_col, :uuid
      backfill_reference_column(fk.from_table, fk.column, fk.to_table, tmp_col)
    end

    unconstrained_refs.each do |from_table, col, to_table|
      tmp_col = temp_uuid_column(col)
      add_column from_table, tmp_col, :uuid
      backfill_reference_column(from_table, col, to_table, tmp_col)
    end

    # 3. Add temporary uuid polymorphic ID columns and backfill per *_type.
    polymorphics.each do |table, type_col, id_col|
      tmp_col = temp_uuid_column(id_col)
      add_column table, tmp_col, :uuid
      backfill_polymorphic_column(table, type_col, id_col, tmp_col, tables)
    end

    # 4. Rewrite JSONB candidacy ID keys in mountain_drafts before old candidacy IDs are dropped.
    backfill_mountain_draft_ratings(tables)

    # 5. Drop dependent views, foreign keys, exclusion/check constraints, and dependent indexes.
    saved_views.reverse_each do |view_name, _definition|
      execute "DROP VIEW #{quote_table_name(view_name)}"
    end

    foreign_keys.each do |fk|
      remove_foreign_key fk.from_table, name: fk.name
    end

    saved_exclusions.each do |table, constraints|
      constraints.each do |name, _definition|
        execute "ALTER TABLE #{quote_table_name(table)} DROP CONSTRAINT #{quote_column_name(name)}"
      end
    end

    saved_checks.each do |table, constraints|
      constraints.each { |cc| remove_check_constraint table, name: cc.name }
    end

    saved_indexes.each do |table, indexes|
      indexes.each { |idx| remove_index table, name: idx.name }
    end

    # 6. Swap primary keys, foreign keys, unconstrained references, polymorphic IDs, and historical ID columns.
    tables.each do |table|
      swap_primary_key(table)
    end

    foreign_keys.each do |fk|
      swap_reference_column(fk.from_table, fk.column, column_nulls.fetch([ fk.from_table, fk.column ]))
    end

    unconstrained_refs.each do |from_table, col, _to_table|
      swap_reference_column(from_table, col, column_nulls.fetch([ from_table, col ]))
    end

    polymorphics.each do |table, _type_col, id_col|
      swap_reference_column(table, id_col, column_nulls.fetch([ table, id_col ]))
    end

    historical_ids.each do |table, col|
      q_table = quote_table_name(table)
      q_col = quote_column_name(col)
      execute "ALTER TABLE #{q_table} ALTER COLUMN #{q_col} TYPE varchar USING #{q_col}::text"
    end

    # 7. Restore indexes, check constraints, exclusion constraints, foreign keys, and views.
    saved_indexes.each do |table, indexes|
      indexes.each { |idx| restore_index(table, idx) }
    end

    saved_checks.each do |table, constraints|
      constraints.each { |cc| add_check_constraint table, cc.expression, name: cc.name }
    end

    saved_exclusions.each do |table, constraints|
      constraints.each do |name, definition|
        execute "ALTER TABLE #{quote_table_name(table)} ADD CONSTRAINT #{quote_column_name(name)} #{definition}"
      end
    end

    foreign_keys.each do |fk|
      restore_foreign_key(fk)
    end

    saved_views.each do |view_name, definition|
      execute "CREATE VIEW #{quote_table_name(view_name)} AS #{definition}"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def target_tables
    connection.tables.uniq.sort.select do |table|
      next false if EXCLUDED_TABLES.include?(table)
      next false if EXCLUDED_TABLE_PREFIXES.any? { |prefix| table.start_with?(prefix) }

      connection.primary_key(table) == "id" && integer_column?(table, "id")
    end
  end

  def integer_column?(table, column_name)
    col = connection.columns(table).find { |c| c.name == column_name.to_s }
    col&.type == :integer
  end

  def temp_uuid_column(column_name)
    "__uuid_#{column_name}"
  end

  def build_converted_columns(tables, foreign_keys, unconstrained_refs, polymorphics)
    map = tables.index_with { Set["id"] }
    foreign_keys.each { |fk| map[fk.from_table] << fk.column.to_s }
    unconstrained_refs.each { |from_table, col, _to_table| map[from_table] << col.to_s }
    polymorphics.each { |table, _type_col, id_col| map[table] << id_col.to_s }
    map
  end

  def capture_dependent_views(tables)
    quoted_tables = tables.map { |t| connection.quote(t) }.join(", ")
    connection.select_rows(<<~SQL.squish)
      WITH RECURSIVE dep_views AS (
        SELECT DISTINCT v.oid, v.relname, 1 AS depth
        FROM pg_depend d
        JOIN pg_rewrite r ON r.oid = d.objid
        JOIN pg_class v ON v.oid = r.ev_class
        JOIN pg_namespace n ON n.oid = v.relnamespace
        JOIN pg_class t ON t.oid = d.refobjid
        WHERE v.relkind = 'v'
          AND n.nspname = current_schema()
          AND t.relname IN (#{quoted_tables})
          AND v.oid <> t.oid
        UNION
        SELECT DISTINCT v.oid, v.relname, dv.depth + 1
        FROM dep_views dv
        JOIN pg_depend d ON d.refobjid = dv.oid
        JOIN pg_rewrite r ON r.oid = d.objid
        JOIN pg_class v ON v.oid = r.ev_class
        JOIN pg_namespace n ON n.oid = v.relnamespace
        WHERE v.relkind = 'v'
          AND n.nspname = current_schema()
          AND v.oid <> dv.oid
      )
      SELECT relname, pg_get_viewdef(oid, true)
      FROM (
        SELECT oid, relname, MAX(depth) AS max_depth
        FROM dep_views
        GROUP BY oid, relname
      ) ordered_views
      ORDER BY max_depth ASC, relname ASC
    SQL
  end

  def capture_exclusion_constraints(tables, converted_columns)
    tables.each_with_object({}) do |table, acc|
      cols = converted_columns.fetch(table)
      rows = connection.select_rows(<<~SQL.squish)
        SELECT conname, pg_get_constraintdef(oid)
        FROM pg_constraint
        WHERE conrelid = #{connection.quote(quote_table_name(table))}::regclass
          AND contype = 'x'
      SQL
      matching = rows.select do |_name, definition|
        cols.any? { |c| definition.match?(/\b#{Regexp.escape(c)}\b/) }
      end
      acc[table] = matching if matching.any?
    end
  end

  def capture_indexes(tables, converted_columns, saved_exclusions)
    tables.each_with_object({}) do |table, acc|
      cols = converted_columns.fetch(table)
      exclusion_names = saved_exclusions.fetch(table, []).map(&:first).to_set
      matching = connection.indexes(table).select do |idx|
        next false if exclusion_names.include?(idx.name)

        idx_cols = Array(idx.columns).map(&:to_s)
        (idx_cols & cols.to_a).any? ||
          (idx.where.present? && cols.any? { |c| idx.where.match?(/\b#{Regexp.escape(c)}\b/) })
      end
      acc[table] = matching if matching.any?
    end
  end

  def capture_check_constraints(tables, converted_columns)
    tables.each_with_object({}) do |table, acc|
      cols = converted_columns.fetch(table)
      matching = connection.check_constraints(table).select do |cc|
        cols.any? { |c| cc.expression.match?(/\b#{Regexp.escape(c)}\b/) }
      end
      acc[table] = matching if matching.any?
    end
  end

  def capture_nullability(tables, foreign_keys, unconstrained_refs, polymorphics)
    columns_by_table = tables.index_with { |t| connection.columns(t).index_by(&:name) }
    result = {}
    foreign_keys.each do |fk|
      result[[ fk.from_table, fk.column ]] = columns_by_table.fetch(fk.from_table).fetch(fk.column).null
    end
    unconstrained_refs.each do |from_table, col, _to_table|
      result[[ from_table, col ]] = columns_by_table.fetch(from_table).fetch(col).null
    end
    polymorphics.each do |table, _type_col, id_col|
      result[[ table, id_col ]] = columns_by_table.fetch(table).fetch(id_col).null
    end
    result
  end

  def backfill_table_uuids(table)
    q_table = quote_table_name(table)
    ts_col = timestamp_column_for(table)
    select_sql = ts_col ? "SELECT id, #{quote_column_name(ts_col)} FROM #{q_table} ORDER BY id ASC" : "SELECT id, NULL FROM #{q_table} ORDER BY id ASC"
    rows = connection.select_rows(select_sql)
    return if rows.empty?

    last_ms = -1
    seq = 0

    pairs = rows.map do |old_id, ts|
      parsed_ts = ts.is_a?(String) ? Time.iso8601(ts) : ts rescue (ts ? Time.parse(ts.to_s) : nil)
      ms = parsed_ts ? (parsed_ts.to_r * 1000).to_i : (Time.now.to_r * 1000).to_i
      ms = 0 if ms.negative?

      if ms <= last_ms
        seq += 1
        if seq > 0x0fff
          last_ms += 1
          seq = 0
        end
        ms = last_ms
      else
        last_ms = ms
        seq = 0
      end

      [ old_id.to_i, build_uuid_v7(ms, seq) ]
    end

    pairs.each_slice(BATCH_SIZE) do |batch|
      values_sql = batch.map { |old_id, uuid| "(#{old_id}::bigint, #{connection.quote(uuid)}::uuid)" }.join(", ")
      execute <<~SQL.squish
        UPDATE #{q_table} AS t
        SET uuid_id = v.uuid_id
        FROM (VALUES #{values_sql}) AS v(old_id, uuid_id)
        WHERE t.id = v.old_id
      SQL
    end
  end

  def timestamp_column_for(table)
    names = connection.columns(table).map(&:name)
    %w[created_at started_at time].find { |candidate| names.include?(candidate) }
  end

  def build_uuid_v7(ms, sequence)
    t_hi = (ms >> 16) & 0xffffffff
    t_lo = ms & 0xffff
    ver_rand_a = 0x7000 | (sequence & 0x0fff)
    rand_b = SecureRandom.random_bytes(8).unpack1("Q>")
    var_rand_b_hi = 0x8000 | ((rand_b >> 48) & 0x3fff)
    rand_b_lo = rand_b & 0xffffffffffff

    format("%08x-%04x-%04x-%04x-%012x", t_hi, t_lo, ver_rand_a, var_rand_b_hi, rand_b_lo)
  end

  def backfill_reference_column(from_table, col, to_table, tmp_col)
    q_from = quote_table_name(from_table)
    q_to = quote_table_name(to_table)
    q_col = quote_column_name(col)
    q_tmp = quote_column_name(tmp_col)

    execute <<~SQL.squish
      UPDATE #{q_from} AS child
      SET #{q_tmp} = parent.uuid_id
      FROM #{q_to} AS parent
      WHERE child.#{q_col} = parent.id
    SQL
  end

  def backfill_polymorphic_column(table, type_col, id_col, tmp_col, tables)
    q_table = quote_table_name(table)
    q_type = quote_column_name(type_col)
    q_id = quote_column_name(id_col)
    q_tmp = quote_column_name(tmp_col)

    types = connection.select_values(<<~SQL.squish)
      SELECT DISTINCT #{q_type}
      FROM #{q_table}
      WHERE #{q_type} IS NOT NULL AND #{q_id} IS NOT NULL
    SQL

    types.each do |type_name|
      target_table = resolve_polymorphic_table(type_name)
      next unless tables.include?(target_table)

      execute <<~SQL.squish
        UPDATE #{q_table} AS poly
        SET #{q_tmp} = target.uuid_id
        FROM #{quote_table_name(target_table)} AS target
        WHERE poly.#{q_type} = #{connection.quote(type_name)}
          AND poly.#{q_id} = target.id
      SQL
    end
  end

  def backfill_mountain_draft_ratings(tables)
    return unless tables.include?("mountain_drafts") && tables.include?("candidacies")

    execute <<~SQL.squish
      UPDATE mountain_drafts AS md
      SET ratings = COALESCE(
        (
          SELECT jsonb_object_agg(c.uuid_id::text, e.value)
          FROM jsonb_each(md.ratings) AS e(key, value)
          JOIN candidacies AS c ON e.key ~ '^[0-9]+$' AND c.id = e.key::bigint
        ),
        '{}'::jsonb
      )
      WHERE md.ratings <> '{}'::jsonb
    SQL
  end

  def resolve_polymorphic_table(type_name)
    type_name.constantize.table_name
  rescue NameError
    type_name.underscore.tr("/", "_").pluralize
  end

  def swap_primary_key(table)
    q_table = quote_table_name(table)
    pk_name = connection.select_value(<<~SQL.squish)
      SELECT conname
      FROM pg_constraint
      WHERE conrelid = #{connection.quote(q_table)}::regclass
        AND contype = 'p'
    SQL

    execute "ALTER TABLE #{q_table} DROP CONSTRAINT #{quote_column_name(pk_name)}" if pk_name
    remove_column table, :id
    rename_column table, :uuid_id, :id
    execute "ALTER TABLE #{q_table} ADD PRIMARY KEY (id)"
  end

  def swap_reference_column(table, col, nullable)
    tmp_col = temp_uuid_column(col)
    if !nullable
      unmatched = connection.select_value(<<~SQL.squish).to_i
        SELECT COUNT(*) FROM #{quote_table_name(table)} WHERE #{quote_column_name(tmp_col)} IS NULL
      SQL
      if unmatched.positive?
        raise "Cannot enforce NOT NULL on #{table}.#{col}: #{unmatched} row(s) had no matching UUID"
      end
    end

    remove_column table, col
    rename_column table, tmp_col, col
    change_column_null table, col, false unless nullable
  end

  def restore_index(table, idx)
    options = { name: idx.name, unique: idx.unique }
    options[:where] = idx.where if idx.where.present?
    options[:order] = idx.orders if idx.orders.present?
    options[:using] = idx.using if idx.using.present? && idx.using != :btree
    options[:opclass] = idx.opclasses if idx.opclasses.present?
    add_index table, idx.columns, **options
  end

  def restore_foreign_key(fk)
    options = { column: fk.column, primary_key: fk.primary_key, name: fk.name }
    options[:on_delete] = fk.on_delete if fk.on_delete
    options[:on_update] = fk.on_update if fk.on_update
    add_foreign_key fk.from_table, fk.to_table, **options
  end
end

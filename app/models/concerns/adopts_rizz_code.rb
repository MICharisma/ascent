# A place that takes a Rizz code (such as MIC-RZZ-LOC-US-NY-NEW_YORK) as its preferred entity_code.
# Its Ascent code and every earlier alias stay bound to it in Ascent's catalog, so seed files, links
# and references that use them keep resolving.
module AdoptsRizzCode
  extend ActiveSupport::Concern

  RIZZ_NAMESPACE = "MIC".freeze
  RIZZ_CATALOG = "RZZ".freeze
  RIZZ_PREFIX = "#{RIZZ_NAMESPACE}-#{RIZZ_CATALOG}-".freeze
  ASCENT_CATALOG = "ASC".freeze

  def rizz_code?
    entity_code.to_s.start_with? RIZZ_PREFIX
  end

  def adopt_rizz_code!(qualified_code)
    raise ArgumentError, "#{qualified_code.inspect} is not a Rizz code" unless qualified_code.to_s.start_with? RIZZ_PREFIX
    return false if entity_code == qualified_code

    transaction do
      lock!
      EntityCode.where(record: self).update_all canonical_code: qualified_code, updated_at: Time.current
      keep_ascent_code_as_alias qualified_code
      EntityCode.find_or_initialize_by(namespace: RIZZ_NAMESPACE, catalog: RIZZ_CATALOG, code: qualified_code.delete_prefix(RIZZ_PREFIX))
        .update! canonical_code: qualified_code, record: self
      update! entity_code: qualified_code
    end
    true
  end

  private

  def keep_ascent_code_as_alias(qualified_code)
    return if entity_code.blank?

    EntityCode.find_or_initialize_by(namespace: RIZZ_NAMESPACE, catalog: ASCENT_CATALOG, code: entity_code)
      .update! canonical_code: qualified_code, record: self
  end
end

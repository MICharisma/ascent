class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  before_create :assign_uuid_v7

  include Hierarchicable

  private

  def assign_uuid_v7
    return unless self.class.columns_hash["id"]&.type == :uuid

    self.id ||= SecureRandom.uuid_v7
  end
end

# A voter's own mark on a record: saving it for later, favoriting it, following it, or hiding it from lists.
class Engagement < ApplicationRecord
  # Records visitors can engage with, by the type name stored in engageable_type.
  ENGAGEABLE_TYPES = %w[Candidacy Race Issue Stance Citizen Municipality Election].freeze

  # Shown to other visitors as a count; bookmarks and hides stay private.
  PUBLIC_KINDS = %w[favorite follow].freeze

  belongs_to :voter
  belongs_to :engageable, polymorphic: true

  enum :kind, { bookmark: "bookmark", favorite: "favorite", follow: "follow", hide: "hide" }, validate: true

  validates :engageable_type, inclusion: { in: ENGAGEABLE_TYPES }
  validates :kind, uniqueness: { scope: [ :voter_id, :engageable_type, :engageable_id ] }

  scope :for_records, ->(records) { where(engageable: records) }
  scope :recent_first, -> { order(created_at: :desc) }

  def self.engageable_class(type_name)
    type_name.constantize if ENGAGEABLE_TYPES.include?(type_name)
  end
end

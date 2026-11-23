# Records that visitors can bookmark, favorite, follow, or hide.
module Engageable
  extend ActiveSupport::Concern

  included do
    has_many :engagements, as: :engageable, dependent: :destroy

    # Leaves out the records this voter has hidden; everyone else sees them all.
    scope :visible_to, ->(voter) {
      voter ? where.not(id: voter.engagements.hide.where(engageable_type: polymorphic_name).select(:engageable_id)) : all
    }
  end
end

# A change to a voter's dimension rating, with the definition in force when it happened.
# Revisions outlive the citizen or policy they describe, and go with the voter's account.
class DimensionRatingRevision < ApplicationRecord
  EVENTS = %w[rate change clear].freeze

  belongs_to :voter

  validates :event, inclusion: { in: EVENTS }
end

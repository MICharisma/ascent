# A Citizen's standing with Rizz. States:
#   pending       not yet sent
#   synced        placed in a Rizz entity, whose code the citizen adopted
#   review        held by Rizz until someone decides an identity review
#   merge_needed  Rizz placed the citizen in an entity another Citizen holds
#   failed        the last attempt could not reach Rizz or conflicted
#   skipped       nothing Rizz can import (fictional, or no name)
#   held          the name's parts need a reading, or triage, before it goes to Rizz
class RizzSync < ApplicationRecord
  STATES = %w[pending synced review merge_needed failed skipped held].freeze

  belongs_to :citizen

  validates :state, inclusion: { in: STATES }
  validates :citizen_id, uniqueness: true
end

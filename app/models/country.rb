class Country < ApplicationRecord
  include JurisdictionOwner
  include AdoptsRizzCode

  has_many :states, dependent: :destroy
  has_many :counties, through: :states
  has_many :municipalities, through: :states

  scope :with_election_stats, -> { includes(:jurisdiction, states: { municipalities: { jurisdiction: :elections } }) }
end

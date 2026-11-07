class State < ApplicationRecord
  include JurisdictionOwner
  include AdoptsRizzCode

  belongs_to :country
  has_many :counties, dependent: :destroy
  has_many :municipalities, dependent: :destroy
  has_many :organizations, dependent: :destroy
  has_many :parties

  scope :in_country, ->(country_id) { where(country_id: country_id) if country_id.present? }
  scope :with_postal_code, ->(code) { where(code: code) }
  scope :with_election_data, -> { includes(:jurisdiction, municipalities: { jurisdiction: :elections }) }
end

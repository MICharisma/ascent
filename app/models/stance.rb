class Stance < ApplicationRecord
  include Engageable

  belongs_to :candidacy
  belongs_to :approach
  has_one :issue, through: :approach
  has_many :stance_evidences, dependent: :destroy
  has_many :communications, through: :stance_evidences

  validates :approach_id, uniqueness: { scope: :candidacy_id, message: "already has a stance from this candidacy" }

  def name
    approach.name + " - " + candidacy.election.name
  end
end

# Ascent's reading of the parts of a Citizen's name, for a name whose columns
# take a shape Rizz can't read on its own. Outcomes:
#   jev       Jev picked a reading with confidence; it goes to Rizz as the name's parts
#   overflow  no reading Jev was sure of; the name waits for a Rizz reviewer
#   settled   a Rizz reviewer chose a reading; it goes to Rizz as the name's parts
#   rejected  a Rizz reviewer found no reading fits; the name columns need correcting
class CitizenNameReading < ApplicationRecord
  OUTCOMES = %w[jev overflow settled rejected].freeze
  READ = %w[jev settled].freeze
  REVIEWED = %w[settled rejected].freeze

  belongs_to :citizen

  validates :outcome, inclusion: { in: OUTCOMES }
  validates :name_text, :shape, :model, presence: true

  # The name as Rizz::Ascent::NameReader reads it from the name columns.
  def self.text_of(citizen)
    [ citizen.first_name, citizen.middle_name, citizen.last_name ].map { it.to_s.strip }.compact_blank.join(" ")
  end

  # Whether this reading is of the citizen's name as it stands.
  def current?
    name_text == self.class.text_of(citizen)
  end
end

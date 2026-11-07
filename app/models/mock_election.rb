# A mock election anyone can make, for teaching or testing: invented races and candidates set in a
# real place. Its offices are inactive and its candidates fictional, so neither passes for the real thing.
#
#   MockElection.new(creator: voter, name: "School board, classroom edition", election_date: 2.weeks.from_now,
#                    jurisdiction_id: city.jurisdiction.id,
#                    races: [ { title: "School Board", candidates: [ "Avery Lin", "Jordan Okafor" ] } ]).save!
class MockElection
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :name, :string
  attribute :description, :string
  attribute :election_date, :date
  attribute :jurisdiction_id, :integer
  attr_accessor :creator, :races
  attr_reader :election

  validates :name, :election_date, :jurisdiction_id, :creator, presence: true
  validate :races_have_titles_and_candidates

  def jurisdiction
    Jurisdiction.find(jurisdiction_id)
  end

  def save!
    validate!
    ActiveRecord::Base.transaction do
      @election = Election.create!(name: name, description: description, election_date: election_date, jurisdiction: jurisdiction,
                                   year: year, kind: "general", status: "upcoming", is_mock: true, is_historical: false, creator: creator)
      races.each { create_race!(**it.to_h.symbolize_keys) }
    end
    election
  end

  private

  def year
    Year.create_with(is_even_year: election_date.year.even?, is_presidential_year: (election_date.year % 4).zero?)
      .find_or_create_by!(year: election_date.year)
  end

  def create_race!(title:, candidates:)
    office = Office.create!(position: Position.find_or_create_by!(title: title), jurisdiction: jurisdiction, is_active: false)
    race = election.races.create!(office: office, status: "upcoming")
    candidates.compact_blank.each { race.candidacies.create!(citizen: fictional_citizen(it), status: "active") }
  end

  def fictional_citizen(full_name)
    *given, last = full_name.split
    Citizen.create!(first_name: given.join(" ").presence, last_name: last, fictional: true)
  end

  def races_have_titles_and_candidates
    errors.add(:races, "need at least one race") if races.blank?
    errors.add(:races, "each need a title and at least two candidates") unless Array(races).all? { complete_race?(**it.to_h.symbolize_keys) }
  end

  def complete_race?(title: nil, candidates: [])
    title.present? && candidates.compact_blank.size >= 2
  end
end

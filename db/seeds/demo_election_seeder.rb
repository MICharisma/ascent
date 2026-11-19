# Fills one real election with invented activity, so its pages can be tried out in development:
# resident and visitor voters who build mountains, invented organizations that endorse candidates,
# follows, and a demo resident to sign in as. Everything it makes is marked as demo data and can be
# removed with clear!. The same election always gets the same data.
#
#   DemoElectionSeeder.new(Election.find(1681)).seed!
class DemoElectionSeeder
  DOMAIN = "demo.ascent.test".freeze
  # The password VoterSeeder gives every seeded voter.
  PASSWORD = "password123".freeze
  RESIDENTS = 30
  VISITORS = 10
  # Every race but the last gets most residents; the last gets only a handful, to see a small sample.
  SHORT_RACE_MOUNTAINS = 4
  ORGANIZATIONS = {
    "Shoreline Neighbors Alliance (demo)" => "civic",
    "Bayside Teachers Guild (demo)" => "union",
    "Marsh Road Small Business Circle (demo)" => "business",
    "The Island Gazette (demo)" => "media",
    "Clean Inlets Project (demo)" => "advocacy",
    "Volunteer Fire Company Auxiliary (demo)" => "civic"
  }.freeze

  attr_reader :election

  def initialize(election)
    @election = election
    seed = election.id.to_s.delete("-").to_i(16)
    @random = Random.new(seed)
    Faker::Config.random = Random.new(seed)
  end

  def seed!
    clear!
    ActiveRecord::Base.transaction do
      endorse_candidates
      residents.each { |voter| build_mountains(voter, resident: true) }
      visitors.each { |voter| build_mountains(voter, resident: false) }
      prepare_demo_resident
      follow_election
    end
    summary
  end

  # Removes this election's demo voters (with their mountains and marks) and demo endorsements,
  # and any demo organization left endorsing no one.
  def clear!
    Voter.where("email LIKE ?", "%.e#{election.id}.%@#{DOMAIN}").destroy_all
    Endorsement.where(candidacy: election.candidacies, endorser: demo_organizations).destroy_all
    demo_organizations.where.missing(:endorsements).destroy_all
  end

  def demo_resident_email
    "demo.resident.e#{election.id}.home@#{DOMAIN}"
  end

  private

  def demo_organizations
    Organization.where(name: ORGANIZATIONS.keys)
  end

  def races
    @races ||= election.races.includes(:candidacies).order(:id).to_a
  end

  def short_race
    races.last
  end

  # How much residents like each candidate, so results lean somewhere rather than sitting at random.
  def appeal
    @appeal ||= races.flat_map(&:candidacies).to_h { [ it.id, @random.rand(80..440) ] }
  end

  def residents
    @residents ||= RESIDENTS.times.map do |n|
      voter = demo_voter("resident#{n + 1}")
      FactoryBot.create(:residence, voter: voter, jurisdiction: election.jurisdiction, status: "active",
        notes: "Demo resident of #{election.jurisdiction.name}")
      voter
    end
  end

  def visitors
    @visitors ||= VISITORS.times.map { |n| demo_voter("visitor#{n + 1}") }
  end

  def demo_voter(label, **attributes)
    FactoryBot.create(:voter, email: "demo.#{label}.e#{election.id}.voter@#{DOMAIN}", first_name: Faker::Name.first_name,
      last_name: Faker::Name.last_name, password: PASSWORD, password_confirmation: PASSWORD, **attributes)
  end

  # Residents build a mountain for most races; visitors try a few. The short race gets only a handful.
  def build_mountains(voter, resident:)
    races.each do |race|
      next unless builds_mountain?(voter, race, resident)

      Mountain.new(voter: voter, race: race).publish!(ratings: ratings_for(race), baseline: rounded(@random.rand(170..340)))
    end
  end

  def builds_mountain?(voter, race, resident)
    return residents.index(voter).to_i < SHORT_RACE_MOUNTAINS if resident && race == short_race

    @random.rand < (resident ? 0.85 : 0.3)
  end

  def ratings_for(race)
    race.candidacies.to_h { [ it.id, rounded((appeal[it.id] + @random.rand(-110..110)).clamp(0, 500)) ] }
  end

  def rounded(value)
    (value / 5.0).round * 5
  end

  # About half the candidates get one to three public endorsements: some strong, some weak, a few withdrawn.
  def endorse_candidates
    organizations = ORGANIZATIONS.map { |name, kind| Organization.find_or_create_by!(name: name, state: nil) { it.kind = kind } }
    races.flat_map(&:candidacies).each do |candidacy|
      next if @random.rand < 0.5

      organizations.sample(@random.rand(1..3), random: @random).each do |organization|
        FactoryBot.create(:endorsement, candidacy: candidacy, endorser: organization, strength: @random.rand(1..5),
          endorsed_on: Date.new(2026, @random.rand(6..10), @random.rand(1..28)),
          withdrawn_on: (Date.new(2026, 10, 15) if @random.rand < 0.1), notes: "Demo data")
      end
    end
  end

  # A resident to sign in as: three races saved, one started but unsaved, and the election followed.
  # They stay off the short race so it keeps its small sample.
  def prepare_demo_resident
    voter = demo_voter("resident", email: demo_resident_email, first_name: "Demo", last_name: "Resident")
    FactoryBot.create(:residence, voter: voter, jurisdiction: election.jurisdiction, status: "active", notes: "Demo resident to sign in as")
    other_races = races - [ short_race ]
    other_races.first(3).each { Mountain.new(voter: voter, race: it).publish!(ratings: ratings_for(it), baseline: 260) }
    Mountain.new(voter: voter, race: other_races[3]).revise_draft!(ratings: ratings_for(other_races[3]), baseline: 240) if other_races[3]
    voter.engagements.create!(engageable: election, kind: "follow")
  end

  def follow_election
    residents.first(12).each { it.engagements.create!(engageable: election, kind: "follow") }
  end

  def summary
    {
      election: election.name,
      voters: RESIDENTS + VISITORS + 1,
      mountains: VoterRaceBaseline.where(race: races).count,
      races_with_mountains: races.count { RaceResults.new(it).any_mountains? },
      short_race: short_race&.office&.name,
      endorsements: Endorsement.where(candidacy: election.candidacies, endorser: demo_organizations).count,
      sign_in_as: demo_resident_email
    }
  end
end

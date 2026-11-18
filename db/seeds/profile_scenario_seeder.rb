require "stringio"

class ProfileScenarioSeeder
  NAME = "New York Civic Forum 2026".freeze
  CANDIDATES = [
    { name: "Marisol Vega", slug: "marisol-vega", bio: "Marisol spent twelve years helping families find stable housing. She now leads a neighborhood services nonprofit and wants state agencies to publish clear service standards.",
      platform: "Build more homes near transit, make school funding predictable, and bring primary care closer to home." },
    { name: "Adrian Cole", slug: "adrian-cole", bio: "Adrian is a former county budget director who helped replace an aging bus fleet. He favors smaller pilot programs with public cost reviews before expansion.",
      platform: "Test improvements locally, publish the full cost, and expand the programs that deliver." },
    { name: "Nia Bennett", slug: "nia-bennett", bio: "Nia is a family physician and former school-board member. Her campaign connects preventive healthcare, reliable transit, and the time families spend navigating public services.",
      platform: "Put prevention first: healthy homes, accessible clinics, dependable buses, and transparent budgets." }
  ].freeze
  POSITIONS = [
    [ "Housing", "Housing affordability", "Build more homes near transit", [
      "Allow apartments near rail stations, with a share reserved for households earning below the local median. Fund water and sewer upgrades alongside new construction.",
      "Offer towns infrastructure grants for housing near stations. Let each town choose its zoning changes, and review construction costs after two years.",
      "Pair transit-area housing with tenant legal assistance and accessibility requirements. Prioritize homes near clinics and existing schools."
    ] ],
    [ "Transportation", "Unreliable bus service", "Run frequent all-day buses", [
      "Fund buses every fifteen minutes on the busiest routes, including evenings. Publish cancelled trips and actual wait times each month.",
      "Pilot frequent service on three routes first. Expand only after comparing passenger numbers, reliability, and operating costs.",
      "Start with routes serving hospitals, community colleges, and shift workers. Make the bus schedule line up with clinic appointments and late shifts."
    ] ],
    [ "Education", "Uneven school funding", "Use a predictable school-funding formula", [
      "Set three-year funding commitments and direct additional support to districts with high student needs. Keep an independent appeals process.",
      "Publish each district's funding calculation and cap annual swings. Commission a cost review before changing the formula.",
      "Count student disability, language needs, and housing instability in the formula. Include school nurses and mental-health staff in the funding commitment."
    ] ],
    [ "Healthcare", "Limited primary-care access", "Bring primary care into underserved neighborhoods", [
      "Support clinics in neighborhoods with long appointment waits. Offer extended hours and publish the time it takes to get a first appointment.",
      "Use mobile clinics to measure demand before opening permanent sites. Publish costs per completed appointment and follow-up rates.",
      "Build long-term primary-care teams with evening hours, interpreters, and follow-up support. Measure continuity of care as well as appointment numbers."
    ] ],
    [ "Government", "Opaque public spending", "Publish searchable contracts and budgets", [
      "Put contracts, amendments, and vendor payments in one searchable site. Release data in a format residents can download and compare.",
      "Publish contracts and audited spending first. Give small agencies a shared reporting tool so the requirement does not create duplicate work.",
      "Connect spending records to the services residents receive. Explain procurement decisions in plain language and publish missed service targets."
    ] ],
    [ "Environment", "Neighborhood flood risk", "Prepare streets and homes for heavy rain", [
      "Prioritize drainage repairs, street trees, and basement-flood prevention in repeatedly flooded neighborhoods. Publish the project schedule.",
      "Rank projects by expected damage avoided per dollar. Fund maintenance before starting expensive new infrastructure.",
      "Start with homes occupied by older residents and citizens with mobility needs. Pair drainage improvements with emergency transport and public-health plans."
    ] ]
  ].freeze

  def seed!
    raise "Profile scenarios are for development and test only" unless Rails.env.development? || Rails.env.test?

    ActiveRecord::Base.transaction do
      creator = Voter.find_by(email: "mara.ellison@example.com") || FactoryBot.create(:voter,
        first_name: "Mara", last_name: "Ellison", email: "mara.ellison@example.com")
      @election = Election.find_by(name: NAME, creator: creator, is_mock: true) || MockElection.new(
        name: NAME, description: "Three invented campaigns for comparing policy positions and profile media.",
        creator: creator, jurisdiction_id: State.find_by!(name: "New York").jurisdiction.id,
        election_date: Date.new(2026, 11, 3), races: [ { title: "Governor", candidates: CANDIDATES.map { it[:name] } } ]).save!
      CANDIDATES.each_with_index { |candidate, index| populate_candidate(candidate, index) }
    end
    { election_id: @election.id, candidacy_ids: @election.candidacies.ids, citizen_ids: @election.candidates.ids }
  end

  private

  def populate_candidate(candidate, index)
    candidacy = @election.candidacies.includes(:citizen).find { it.citizen.full_name == candidate[:name] }
    candidacy.citizen.update!(bio: candidate[:bio])
    candidacy.update!(platform_summary: candidate[:platform])
    website = Channel.find_or_initialize_by(platform: "website", handle: "#{candidate[:slug]}-civic-forum")
    website.update!(owner: candidacy, official: true, url: "https://ascent.test/profiles/#{candidate[:slug]}.html")

    POSITIONS.each_with_index do |(topic_title, issue_title, approach_title, explanations), position|
      topic = Topic.find_or_create_by!(title: topic_title)
      issue = Issue.find_or_create_by!(title: issue_title, topic: topic)
      approach = Approach.find_or_create_by!(title: approach_title, issue: issue)
      stance = candidacy.stances.find_or_initialize_by(approach: approach)
      stance.update!(explanation: explanations[index], priority_level: position < 3 ? "high" : "medium", evidence_links: nil)
    end
    return unless index.zero?

    image = Image.find_or_initialize_by(url: "https://ascent.test/portraits/marisol-vega.png")
    image.update!(credit: "AI-generated portrait", alt_text: "Portrait of Marisol Vega")
    unless image.file.attached?
      image.file.attach(io: StringIO.new(File.binread(Rails.root.join("public/portraits/marisol-vega.png"))),
        filename: "marisol-vega.png", content_type: "image/png", metadata: { ai_generated: true })
    end
    candidacy.citizen.image_placements.find_or_create_by!(image: image)
    social = Channel.find_or_initialize_by(platform: "bluesky", handle: "marisolvega.example")
    social.update!(owner: candidacy.citizen, official: true, url: "https://bsky.app/profile/marisolvega.example")
    video = Communication.find_or_initialize_by(url: "https://ascent.test/media/marisol-vega-introduction.mp4")
    video.update!(channel: website, kind: "video", title: "Meet Marisol Vega", published_on: Date.new(2026, 10, 15),
      summary: "A campaign introduction covering housing, school funding, and primary care. A generated portrait with synthesized narration for this invented candidate.")
    video.communication_features.find_or_create_by!(candidacy: candidacy)
    demonstration = Communication.find_or_initialize_by(url: "https://www.youtube.com/watch?v=M7lc1UVf-VE")
    demonstration.update!(kind: "video", title: "Try an embedded YouTube player", published_on: Date.new(2026, 10, 14),
      summary: "YouTube's public player demonstration. Included to try the embedded player; this is not campaign footage.")
    demonstration.communication_features.find_or_create_by!(candidacy: candidacy)
  end
end

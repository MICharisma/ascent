# frozen_string_literal: true

# A citizen who has stood for office: who they are, every candidacy as a timeline from the latest back,
# and where their latest candidacy stands. Their channels and the races they ran in sit beside.
class Views::Citizens::ShowView < Views::ApplicationView
  prop :citizen, Citizen

  def view_template
    div(class: "record-page citizen-page", id: dom_id(@citizen, :show)) do
      div(class: "profile-header") do
        PageHeader(title: @citizen.full_name, trail: trail_for(@citizen), eyebrow: eyebrow, lede: lede, record: @citizen,
          chips: method(:chips)) do
          PillLink(label: "Latest candidacy", path: candidacy_path(latest), icon: :badge_check) if latest
        end
        ProfilePortrait(citizen: @citizen, image: images.first)
      end
      div(class: "place-layout") do
        div(class: "place-main") do
          ProfileImages(citizen: @citizen, images: images)
          CommunicationGallery(communications: communications)
          candidacies_section
          latest_stances
        end
        aside(class: "place-aside", aria: { label: "About #{@citizen.full_name}" }) do
          facts_card
          OfficialChannels(owners: [ @citizen, *candidacies ])
          admin_card
        end
      end
    end
  end

  private

  # Latest election first.
  def candidacies
    @candidacies ||= @citizen.candidacies.includes(:ballot_lines, race: [ :election, { office: [ :position, { jurisdiction: :jurisdictionable } ] } ])
      .sort_by { -it.race.election.election_date.jd }
  end

  def latest
    candidacies.first
  end

  def communications
    Communication.for_profile(@citizen, candidacies).includes(:channel).order(published_on: :desc, id: :desc).limit(8).to_a
  end

  def images
    @images ||= @citizen.images.to_a
  end

  def eyebrow
    latest ? "Candidate · #{latest.race.office.jurisdiction.name}" : "Citizen"
  end

  def lede
    return @citizen.bio if @citizen.bio.present?
    return "#{@citizen.full_name} has no candidacies on Ascent yet." unless latest

    "Running for #{latest.race.office.name} in the #{latest.race.election.name}." +
      (candidacies.many? ? " #{pluralize(candidacies.size - 1, "earlier candidacy", plural: "earlier candidacies")} below." : "")
  end

  def chips
    span(class: "row-badge row-badge-mock") { "Invented for a mock election" } if @citizen.fictional
    latest&.ballot_lines&.each { |line| span(class: "place-chip") { line.label } }
  end

  def candidacies_section
    section(class: "place-section", id: "citizen-candidacies") do
      section_heading("Candidacies", pluralize(candidacies.size, "race"))
      if candidacies.any?
        ol(class: "list-rows", data: { controller: "reveal" }) { candidacies.each { candidacy_row(it) } }
      else
        p(class: "card-text") { "No candidacies are recorded for #{@citizen.full_name}." }
      end
    end
  end

  def candidacy_row(candidacy)
    race = candidacy.race
    ListRow(record: candidacy, title: race.office.name,
      meta: "#{race.election.name} · #{race.election.election_date.strftime("%b %-d, %Y")}", detail: candidacy.ballot_labels) do
      StatusChip(status: candidacy.status.downcase)
    end
  end

  def latest_stances
    return unless latest

    stances = latest.stances.includes(:stance_evidences, approach: { issue: :topic }).to_a
    return if stances.empty?

    section(class: "place-section") do
      section_heading("Where they stand", "as candidate for #{latest.race.office.position.title}")
      StanceList(stances: stances)
    end
  end

  def facts_card
    SideCard(heading: "At a glance") do
      dl(class: "place-facts-list") do
        FactRow(label: "Candidacies", value_class: "glance-value") { candidacies.size.to_s }
        FactRow(label: "First on a ballot") { candidacies.last.race.election.election_date.year.to_s } if candidacies.any?
        FactRow(label: "Latest race") { link_to latest.race.office.name, latest.race, class: "text-link" } if latest
      end
    end
  end

  def admin_card
    return unless current_voter&.admin?

    SideCard(heading: "Admin", modifier: "admin-card") { Ui::ResourceActions(resource: @citizen) }
  end
end

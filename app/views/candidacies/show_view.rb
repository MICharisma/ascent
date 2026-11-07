# frozen_string_literal: true

# A candidate as a citizen running for one seat: who they are and how they appear on the ballot, where they
# stand by topic, who endorses them, where they speak for themselves, and how voters rate them, in total
# only. The side column places the candidacy in its race, and leaves room for evaluations to come.
class Views::Candidacies::ShowView < Views::ApplicationView
  ENDORSEMENT_LIMIT = 8
  COMMUNICATION_LIMIT = 5
  RIVAL_LIMIT = 8

  prop :candidacy, Candidacy

  def view_template
    div(class: "record-page candidacy-page", id: dom_id(@candidacy, :show)) do
      div(class: "profile-header") do
        PageHeader(title: citizen.full_name, trail: trail_for(@candidacy), eyebrow: eyebrow, lede: lede, record: @candidacy,
          chips: method(:chips)) do
          primary_action
          PillLink(label: "Citizen page", path: citizen_path(citizen), icon: :user_round, variant: "outline")
        end
        ProfilePortrait(citizen: citizen, image: images.first)
      end
      div(class: "place-layout") do
        div(class: "place-main") do
          ProfileImages(citizen: citizen, images: images)
          communications_section
          stances_section
          endorsements_section
          rating_totals
          rivals
        end
        aside(class: "place-aside", aria: { label: "About this candidacy" }) do
          race_card
          OfficialChannels(owners: [ citizen, @candidacy ])
          admin_card
        end
      end
    end
  end

  private

  def citizen
    @candidacy.citizen
  end

  def race
    @candidacy.race
  end

  def election
    race.election
  end

  def eyebrow
    "Candidate for #{race.office.name} · #{election.election_date.strftime("%b %-d, %Y")}"
  end

  def lede
    @candidacy.platform_summary.presence || "#{citizen.full_name} is running for #{race.office.name} in the #{election.name}."
  end

  def chips
    span(class: "row-badge row-badge-mock") { "Invented for a mock election" } if citizen.fictional
    StatusChip(status: @candidacy.status.downcase)
    labels = @candidacy.ballot_lines.map(&:label)
    labels = [ @candidacy.primary_summary ] if labels.empty? && @candidacy.primary_candidacy
    labels.each { |label| span(class: "place-chip") { label } }
  end

  def rateable?
    election.open_to_rating? || election.mode == "historical"
  end

  def primary_action
    if !current_voter
      PillLink(label: "Sign in to rate them", path: new_voter_session_path, icon: :mountain)
    elsif rateable?
      PillLink(label: "Rate them on your mountain", path: edit_mountain_path(race), icon: :mountain)
    else
      PillLink(label: "See the race", path: race_path(race), icon: :vote)
    end
  end

  def stances
    @stances ||= @candidacy.stances.includes(:stance_evidences, approach: { issue: :topic }).to_a
  end

  def stances_section
    section(class: "place-section", id: "candidacy-stances") do
      section_heading("Where they stand", (pluralize(stances.size, "stance") if stances.any?))
      if stances.any?
        StanceList(stances: stances)
      else
        p(class: "card-text") do
          "No stances are recorded yet. A stance ties a candidate to an approach on an issue, with evidence from what they have said."
        end
        link_to topics_path, class: "text-link" do
          plain "Browse the topics"
          icon(:chevron_right)
        end
      end
    end
  end

  def endorsements
    @endorsements ||= @candidacy.endorsements.current.strongest_first.includes(:endorser).to_a
  end

  def endorsements_section
    return if endorsements.empty?

    section(class: "place-section") do
      section_heading("Endorsements", pluralize(endorsements.size, "endorsement"))
      ul(class: "endorsement-list") { endorsements.first(ENDORSEMENT_LIMIT).each { endorsement_item(it) } }
      p(class: "card-text") { "And #{pluralize(endorsements.size - ENDORSEMENT_LIMIT, "more")}." } if endorsements.size > ENDORSEMENT_LIMIT
    end
  end

  def endorsement_item(endorsement)
    li(class: "endorsement-item") do
      strong(class: "endorsement-name") { link_to endorsement.endorser.name, endorsement.endorser, class: "text-link" }
      span(class: "endorsement-kind") do
        endorsement.kind == "ballot_line" ? "Party line" : [ "Endorsed", endorsement.endorsed_on&.strftime("%b %Y") ].compact.join(" · ")
      end
    end
  end

  def communications_section
    communications = Communication.for_profile(citizen, [ @candidacy ]).includes(:channel)
      .order(published_on: :desc, id: :desc).limit(COMMUNICATION_LIMIT).to_a
    CommunicationGallery(communications: communications)
  end

  def images
    @images ||= (@candidacy.images.to_a + citizen.images.to_a).uniq(&:id)
  end

  # Only totals: a rating is private to its voter, so no one may see who rated the candidate or how.
  def rating_totals
    section(class: "place-section candidacy-ratings") do
      section_heading("Ratings", nil)
      if @candidacy.ratings.any?
        div(class: "stats-grid") do
          Stat(value: @candidacy.ratings.count, label: "voters rated")
          Stat(value: @candidacy.average_rating.to_f, label: "average rating")
          Stat(value: @candidacy.approvals_count, label: "approve")
        end
      else
        p(class: "candidacy-ratings-empty") { "No voter has rated this candidate yet." }
      end
      privacy_line
    end
  end

  def privacy_line
    p(class: "privacy-line") do
      icon(:lock)
      plain "Totals only. Ascent never shows who rated a candidate or how."
    end
  end

  def rivals
    others = race.candidacies.where.not(id: @candidacy.id).includes(:citizen, :ballot_lines).sort_by { it.citizen.last_name.to_s }
    RelatedList(heading: "Also running for #{race.office.position.title}", records: others.first(RIVAL_LIMIT), total: others.size,
      see_all: race_path(race, anchor: "race-candidates"), noun: "candidates") do |candidacy|
      ListRow(record: candidacy, title: candidacy.citizen.full_name, meta: candidacy.ballot_labels)
    end
  end

  def race_card
    SideCard(heading: "The race") do
      dl(class: "place-facts-list") do
        FactRow(label: "Office") { link_to race.office.name, race, class: "text-link" }
        FactRow(label: "Election") { link_to election.name, election, class: "text-link" }
        FactRow(label: "Date") { "#{election.election_date.strftime("%b %-d, %Y")} · #{relative_days(election.election_date)}" }
        FactRow(label: "Announced") { @candidacy.announcement_date.strftime("%b %-d, %Y") } if @candidacy.announcement_date
      end
      link_to race_path(race, anchor: "race-candidates"), class: "text-link" do
        plain "All #{pluralize(race.candidacies.size, "candidate")}"
        icon(:chevron_right)
      end
    end
  end

  def admin_card
    return unless current_voter&.admin?

    SideCard(heading: "Admin", modifier: "admin-card") { Ui::ResourceActions(resource: @candidacy) }
  end
end

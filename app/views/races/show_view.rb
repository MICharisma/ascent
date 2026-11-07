# frozen_string_literal: true

# A race's page leads with its candidates and the way to rate them. Candidates the primaries eliminated
# follow as their own group, at the same weight. Once mountains are saved, the approval tally so far;
# then the office's earlier races. The side column places the race: its office, its election, and admin.
class Views::Races::ShowView < Views::ApplicationView
  RESULT_LIMIT = 5
  EARLIER_RACE_LIMIT = 5

  prop :race, Race

  def view_template
    div(class: "record-page race-page", id: dom_id(@race, :show)) do
      PageHeader(title: office.position.title, trail: trail_for(@race), eyebrow: eyebrow, lede: lede, record: @race,
        chips: method(:chips)) do
        primary_action
        results_link if results
      end
      div(class: "place-layout") do
        div(class: "place-main") do
          ballot_candidates
          primary_candidates
          results_section if results
          earlier_races
        end
        aside(class: "place-aside", aria: { label: "About this race" }) do
          office_card
          election_card
          source_card
          admin_card
        end
      end
    end
  end

  private

  def office
    @race.office
  end

  def election
    @race.election
  end

  def candidacies
    @candidacies ||= @race.candidacies.includes(:citizen, :ballot_lines, primary_candidacy: { office: :nominating_organization })
      .sort_by { [ it.citizen.last_name.to_s, it.citizen.first_name.to_s ] }
  end

  def on_ballot
    candidacies.reject(&:primary_candidacy_id)
  end

  def from_primaries
    candidacies.select(&:primary_candidacy_id)
  end

  def eyebrow
    [ office.jurisdiction.name, office.seat_label, election.election_date.strftime("%a %b %-d, %Y") ].compact.join(" · ")
  end

  def lede
    "#{candidate_count_text} #{date_text}"
  end

  def candidate_count_text
    text = "#{pluralize(on_ballot.size, "candidate")} on the ballot"
    text += ", and #{pluralize(from_primaries.size, "other")} who ran in the primaries" if from_primaries.any?
    "#{text}."
  end

  def date_text
    days = election.days_until
    if days.positive? then "Election day is in #{pluralize(days, "day")}."
    elsif days.zero? then "Election day is today."
    else "Decided on #{election.election_date.strftime("%B %-d, %Y")}."
    end
  end

  def chips
    StatusChip(status: @race.status)
    span(class: "row-badge row-badge-#{election.mode}") { election.mode == "mock" ? "Mock election" : "Historical" } unless election.mode == "real"
    span(class: "row-badge row-badge-yours") { "On your ballot" } if resident?
  end

  def resident?
    return @resident if defined?(@resident)

    @resident = current_voter&.resident_of?(@race) || false
  end

  def progress
    @progress ||= current_voter ? current_voter.mountain_progress(Race.where(id: @race.id))[@race.id] : nil
  end

  def rateable?
    election.open_to_rating? || election.mode == "historical"
  end

  def primary_action
    if !current_voter
      PillLink(label: "Sign in to build a mountain", path: new_voter_session_path, icon: :mountain)
    elsif rateable? && on_ballot.any?
      PillLink(label: cta_text, path: edit_mountain_path(@race), icon: :mountain, variant: (resident? ? nil : "summit"))
    end
  end

  def cta_text
    case progress
    when "saved" then "Open your mountain"
    when "started" then "Keep going"
    else
      return "Replay with approval" if election.mode == "historical"

      resident? || election.mode == "mock" ? "Build your mountain" : "Pretend vote"
    end
  end

  def results_link
    PillLink(label: "Results", path: race_results_path(@race), icon: :chart_column, variant: "outline")
  end

  def ballot_candidates
    section(class: "place-section", id: "race-candidates") do
      section_heading("On the ballot", pluralize(on_ballot.size, "candidate"))
      if on_ballot.any?
        ul(class: "list-rows", data: { controller: "reveal" }) { on_ballot.each { candidate_row(it, it.ballot_labels) } }
      else
        p(class: "card-text") { "No candidates have filed for this race yet." }
      end
    end
  end

  def primary_candidates
    return if from_primaries.empty?

    section(class: "place-section race-primaries") do
      section_heading("Ran in the primaries", pluralize(from_primaries.size, "candidate"))
      p(class: "card-text") do
        "The primaries took them off the ballot. Voters who choose to can still rate them on their mountain, " \
          "to see how approval would have treated them."
      end
      ul(class: "list-rows", data: { controller: "reveal" }) { from_primaries.each { candidate_row(it, it.primary_summary) } }
    end
  end

  def candidate_row(candidacy, labels)
    ListRow(record: candidacy, title: candidacy.citizen.full_name, meta: labels) do
      StatusChip(status: candidacy.status.downcase) unless %w[active announced].include?(candidacy.status.downcase)
    end
  end

  # Residents' mountains when there are any, otherwise visitors'.
  def results
    return @results if defined?(@results)

    @results = RaceResults::GROUPS.lazy.map { @race.results_for(it) }.find { it[:any_mountains] }
  end

  def results_section
    shares = results[:approval_shares].sort_by { -it.last }
    names = candidacies.index_by(&:id)
    section(class: "place-section race-results") do
      section_heading("Approval so far", "#{delimited(results[:mountain_count])} #{results[:group] == "resident" ? "resident" : "visitor"} #{"mountain".pluralize(results[:mountain_count])}")
      ol(class: "approval-bars") do
        shares.first(RESULT_LIMIT).each { |candidacy_id, share| approval_bar(names[candidacy_id], share) }
      end
      link_to race_results_path(@race, group: results[:group]), class: "text-link" do
        plain "See the full results"
        icon(:chevron_right)
      end
    end
  end

  def approval_bar(candidacy, share)
    return unless candidacy

    li(class: "approval-bar") do
      span(class: "approval-bar-name") { candidacy.citizen.full_name }
      span(class: "approval-bar-track", aria: { hidden: true }) do
        span(class: "approval-bar-fill", style: "--share: #{share.round}%")
      end
      span(class: "approval-bar-value") { percent(share) }
    end
  end

  def earlier_races
    races = office.races.where.not(id: @race.id).recent.includes(:election, :candidacies)
    RelatedList(heading: "Other races for this office", records: races.limit(EARLIER_RACE_LIMIT).to_a, total: races.count,
      see_all: office_races_path(office), noun: "races") do |race|
      ListRow(record: race, title: race.election.name,
        meta: "#{race.election_date.strftime("%b %-d, %Y")} · #{pluralize(race.candidacies.size, "candidate")}") do
        StatusChip(status: race.status)
      end
    end
  end

  def office_card
    SideCard(heading: "The office") do
      dl(class: "place-facts-list") do
        FactRow(label: "Office") { link_to office.name, office, class: "text-link" }
        FactRow(label: "Position") { link_to office.position.title, office.position, class: "text-link" }
        FactRow(label: "Where") { link_to office.jurisdiction.name, office.jurisdiction.jurisdictionable, class: "text-link" }
        current_holder
      end
    end
  end

  def current_holder
    holder = office.current_office_holder
    return unless holder

    FactRow(label: "Approval winner, last race") { link_to holder.citizen.full_name, holder.citizen, class: "text-link" }
  end

  def election_card
    SideCard(heading: "The election") do
      dl(class: "place-facts-list") do
        FactRow(label: "Election") { link_to election.name, election, class: "text-link" }
        FactRow(label: "Date") { "#{election.election_date.strftime("%b %-d, %Y")} · #{relative_days(election.election_date)}" }
        FactRow(label: "Kind") { election.kind.humanize } if election.kind.present?
      end
      other_races_link
    end
  end

  def other_races_link
    others = election.races.where.not(id: @race.id).count
    return if others.zero?

    link_to races_path(election_id: election.id), class: "text-link" do
      plain "#{pluralize(others, "other race")} on this ballot"
      icon(:chevron_right)
    end
  end

  # Where the race's data came from, as the importer recorded it.
  def source_card
    return if @race.description.blank?

    SideCard(heading: "Source", modifier: "source-card") do
      div(class: "card-text") { simple_format(@race.description) }
    end
  end

  def admin_card
    return unless current_voter&.admin?

    SideCard(heading: "Admin", modifier: "admin-card") do
      Ui::ResourceActions(resource: @race)
      simulate_button if @race.mock? && can_simulate_mountains?
    end
  end

  def simulate_button
    button_to simulate_mountain_path(@race), method: :post, class: "resource-action resource-action-simulate", form_class: "resource-action-form" do
      Ui::ActionIcon(kind: :simulate)
      span { "Simulate data" }
    end
  end
end

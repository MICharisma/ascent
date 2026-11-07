# frozen_string_literal: true

# An office: where it sits, its next race with the candidates and the way to rate them, then every race
# for it from the latest back. The side column says what kind of seat it is and who last won it here.
class Views::Offices::ShowView < Views::ApplicationView
  prop :office, Office

  def view_template
    div(class: "record-page office-page", id: dom_id(@office, :show)) do
      PageHeader(title: @office.position.title, trail: trail_for(@office), eyebrow: eyebrow, lede: lede, record: @office,
        icon_for: @office, chips: method(:chips)) do
        next_race_action
        PillLink(label: "All races", path: office_races_path(@office), icon: :vote, variant: "outline") if races.any?
      end
      stat_tiles
      div(class: "place-layout") do
        div(class: "place-main") do
          next_race_section
          history_section
        end
        aside(class: "place-aside", aria: { label: "About this office" }) do
          seat_card
          nominations_card
          notes_card
          admin_card
        end
      end
    end
  end

  private

  def races
    @races ||= @office.races.includes(:election, candidacies: [ :citizen, :ballot_lines ]).sort_by { -it.election.election_date.jd }
  end

  def next_race
    @next_race ||= races.select { ahead?(it) }.min_by { it.election.election_date }
  end

  def eyebrow
    [ @office.jurisdiction.name, @office.seat_label, @office.branch&.humanize ].compact_blank.join(" · ")
  end

  def lede
    return "#{@office.name}. No race for it is on Ascent yet." if races.empty?
    return "#{@office.name}. Its most recent race was the #{races.first.election.name}." unless next_race

    "#{@office.name}. Next decided in the #{next_race.election.name}, #{relative_days(next_race.election.election_date)}, " \
      "among #{pluralize(next_race.candidacies.size, "candidate")}."
  end

  def chips
    span(class: "row-badge") { "Inactive" } unless @office.is_active
    span(class: "row-badge") { "Nomination" } if @office.nomination?
  end

  def next_race_action
    return unless next_race

    PillLink(label: "See the next race", path: race_path(next_race), icon: :chevron_right)
  end

  def stat_tiles
    return if races.empty?

    div(class: "stat-tiles place-facts") do
      StatTile(value: races.size.to_s, label: "#{"race".pluralize(races.size)} on Ascent")
      StatTile(value: races.sum { it.candidacies.size }.to_s, label: "candidacies across them")
      if next_race
        StatTile(value: next_race.election.election_date.strftime("%b %-d"), label: "next election · #{relative_days(next_race.election.election_date)}",
          modifier: "date")
      end
    end
  end

  def next_race_section
    return unless next_race

    candidacies = next_race.candidacies.reject(&:primary_candidacy_id).sort_by { it.citizen.last_name.to_s }
    section(class: "place-section", id: "office-next-race") do
      section_heading("On the ballot next", "#{next_race.election.name} · #{next_race.election.election_date.strftime("%b %-d, %Y")}")
      if candidacies.any?
        ul(class: "list-rows", data: { controller: "reveal" }) do
          candidacies.each { ListRow(record: it, title: it.citizen.full_name, meta: it.ballot_labels) }
        end
      else
        p(class: "card-text") { "No candidates have filed yet." }
      end
      link_to race_path(next_race), class: "text-link" do
        plain "Open the race"
        icon(:chevron_right)
      end
    end
  end

  def history_section
    earlier = races - [ next_race ]
    RelatedList(heading: next_race ? "Other races" : "Races", records: earlier.first(8), total: earlier.size,
      see_all: office_races_path(@office), noun: "races", empty: (races.empty? ? "No race for this office is on Ascent yet." : nil)) do |race|
      ListRow(record: race, title: race.election.name,
        meta: "#{race.election.election_date.strftime("%b %-d, %Y")} · #{pluralize(race.candidacies.size, "candidate")}") do
        StatusChip(status: race.status)
      end
    end
  end

  def seat_card
    SideCard(heading: "The seat") do
      dl(class: "place-facts-list") do
        FactRow(label: "Position") { link_to @office.position.title, @office.position, class: "text-link" }
        FactRow(label: "Where") { link_to @office.jurisdiction.name, @office.jurisdiction.jurisdictionable, class: "text-link" }
        FactRow(label: "Body") { link_to @office.governing_body.name, @office.governing_body, class: "text-link" } if @office.governing_body
        FactRow(label: "Chamber") { @office.chamber.name } if @office.chamber
        FactRow(label: "Seat") { @office.seat_label } if @office.seat_label
        last_winner
      end
    end
  end

  # Ascent's own count: the approval winner of the last finished race, not the official result.
  def last_winner
    winner = @office.current_office_holder
    return unless winner

    FactRow(label: "Approval winner, last race") { link_to winner.citizen.full_name, winner.citizen, class: "text-link" }
  end

  def nominations_card
    if @office.nomination?
      SideCard(heading: "Nominates for") { link_to @office.nominee_for.name, @office.nominee_for, class: "text-link" }
    elsif @office.nominations.any?
      SideCard(heading: "Nominations") do
        ul(class: "nearby-list") { @office.nominations.includes(:nominating_organization).each { |nomination| li { link_to nomination.nominating_organization.name, nomination, class: "text-link" } } }
      end
    end
  end

  def notes_card
    return if @office.notes.blank?

    SideCard(heading: "Notes", modifier: "source-card") { div(class: "card-text") { simple_format(@office.notes) } }
  end

  def admin_card
    return unless current_voter&.admin?

    SideCard(heading: "Admin", modifier: "admin-card") do
      Ui::ResourceActions(resource: @office)
      scaffold_new_resource_link "Add a race", new_race_path, record: Race
    end
  end
end

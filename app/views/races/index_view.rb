# frozen_string_literal: true

# Every race, most recent election first: tabs by status, then filters that lead with place ("Where I
# live", then state) before year and kind. Each row names the office, its election and candidates, and
# for a signed-in voter whether the race is on their ballot and how far their mountain has got.
class Views::Races::IndexView < Views::ApplicationView
  TABS = { nil => "All", "active" => "Active", "upcoming" => "Upcoming", "completed" => "Completed", "cancelled" => "Cancelled" }.freeze
  CANDIDATE_NAME_LIMIT = 3

  prop :races, ActiveRecord::Relation
  prop :pagy, _Nilable(Pagy)
  prop :filters, Hash
  prop :scope, Hash
  prop :scope_record, _Nilable(_Union(Office, Election))
  prop :status_counts, Hash
  prop :states, ActiveRecord::Relation
  prop :years, Array
  prop :kinds, Array

  def view_template
    IndexPage(title: title, records: @races, pagy: @pagy, noun: "race", frame: "races-list", eyebrow: "Races", lede: lede,
      trail: trail, clear_path: races_path(@scope), actions: (method(:new_race_link) if scaffold_new_resource_visible?(Race)),
      tabs: method(:status_tabs), filters: method(:filter_bar)) { race_row(it) }
  end

  private

  def title
    case @scope_record
    when Office then "Races for #{@scope_record.name}"
    when Election then "Races on the #{@scope_record.name}"
    else "Every race"
    end
  end

  def trail
    @scope_record ? [ [ "Races", races_path ], [ @scope_record.name, @scope_record ] ] : [ [ "Elections", elections_path ] ]
  end

  def lede
    total = @status_counts.values.sum
    open = @status_counts.slice(*Election::OPEN_STATUSES).values.sum
    "#{delimited(total)} #{"race".pluralize(total)}, #{delimited(open)} still open for mountains. " +
      (lives_somewhere? ? "Choose “Where I live” to see only those on your ballot." : "Pick a state to find the races on your ballot.")
  end

  def new_race_link
    PillLink(label: "New race", path: new_race_path(@scope.slice("election_id")), icon: :plus)
  end

  def status_tabs
    nav(class: "listing-tabs", aria: { label: "Races by status" }) do
      TABS.each do |status, label|
        count = status ? @status_counts.fetch(status, 0) : @status_counts.values.sum
        next if status == "cancelled" && count.zero?

        current = status == @filters["status"].presence
        link_to listing_path(status: status), class: "listing-tab#{" is-current" if current}", aria: { current: (current ? "page" : nil) } do
          span(class: "listing-tab-label") { label }
          span(class: "listing-tab-count") { delimited(count) }
        end
      end
    end
  end

  def filter_bar
    near_chip if lives_somewhere?
    filter_form
  end

  def near_chip
    near = @filters["near"].present?
    link_to listing_path(near: (near ? nil : "1")), class: "filter-chip filter-chip-near#{" is-current" if near}", aria: { pressed: near.to_s } do
      icon(:map_pin)
      plain "Where I live"
    end
  end

  def filter_form
    FilterForm(url: races_path, label: "Filter races", placeholder: "Office, election, candidate or place", values: @filters,
      clear_path: races_path(@scope), hidden: @scope.merge("status" => @filters["status"], "near" => @filters["near"]),
      selects: [
        [ :state_id, "State", @states.map { [ it.name, it.id ] }, "All states" ],
        [ :year, "Election year", @years, "All years" ],
        [ :kind, "Election kind", @kinds.map { [ it.humanize, it ] }, "All kinds" ]
      ])
  end

  # The current filters with some changed, dropping the ones that are off.
  def listing_path(**changes)
    races_path(@scope.merge(@filters).merge(changes.stringify_keys).compact_blank)
  end

  def race_row(race)
    ListRow(record: race, title: race.office.name, meta: race_meta(race), detail: candidate_names(race),
      modifier: ("is-yours" if yours?(race))) do
      race_badges(race)
      simulate_button(race)
    end
  end

  def race_meta(race)
    election = race.election
    [ election.name, election.election_date.strftime("%b %-d, %Y"), pluralize(race.candidacies.size, "candidate") ].join(" · ")
  end

  def candidate_names(race)
    names = race.candidacies.reject(&:primary_candidacy_id).map { it.citizen.display_name }
    return if names.empty?

    shown = names.first(CANDIDATE_NAME_LIMIT).join(", ")
    names.size > CANDIDATE_NAME_LIMIT ? "#{shown}, and #{names.size - CANDIDATE_NAME_LIMIT} more" : shown
  end

  def race_badges(race)
    mode = race.election.mode
    span(class: "row-badge row-badge-#{mode}") { mode == "mock" ? "Mock" : "Historical" } unless mode == "real"
    span(class: "row-badge row-badge-yours") { "Your ballot" } if yours?(race)
    span(class: "row-badge row-badge-#{progress[race.id]}") { progress[race.id] == "saved" ? "Mountain saved" : "Started" } if progress[race.id]
    StatusChip(status: race.status)
  end

  def simulate_button(race)
    return unless can_simulate_mountains? && race.mock?

    button_to simulate_mountain_path(race), method: :post, class: "icon-action list-row-action",
      form_class: "inline-form", aria: { label: "Simulate data for #{race.office.name}" }, title: "Simulate data" do
      Ui::ActionIcon(kind: :simulate)
    end
  end

  def yours?(race)
    resident_jurisdiction_ids.include?(race.office.jurisdiction_id)
  end

  def lives_somewhere?
    return @lives_somewhere if defined?(@lives_somewhere)

    @lives_somewhere = current_voter&.current_residences&.any? || false
  end

  def resident_jurisdiction_ids
    @resident_jurisdiction_ids ||= lives_somewhere? ? current_voter.ballot_jurisdictions.pluck(:id).to_set : Set.new
  end

  def progress
    @progress ||= current_voter ? current_voter.mountain_progress(Race.where(id: @races.map(&:id))) : {}
  end
end

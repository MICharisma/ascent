# frozen_string_literal: true

# Every election, as a calendar: tabs for open, past, mock and historical elections, filters for kind,
# place and where the voter lives, then the elections grouped under sticky day headers. Each row shows
# what is on its ballot and, for a signed-in voter, whether it is theirs and how far they have got.
class Views::Elections::IndexView < Views::ApplicationView
  TAB_LABELS = { "upcoming" => "Upcoming", "past" => "Past", "mock" => "Mock", "historical" => "Historical", "all" => "All" }.freeze
  KIND_LABELS = { "general" => "General", "primary" => "Primary", "special" => "Special" }.freeze
  BALLOT_PREVIEW_LIMIT = 3

  prop :elections, ActiveRecord::Relation
  prop :pagy, _Nilable(Pagy)
  prop :filters, Hash
  prop :tab_counts, Hash
  prop :day_counts, Hash

  def view_template
    div(class: "elections-page") do
      elections_header
      your_elections
      listing_tabs
      listing_filters
      if @elections.any?
        ol(class: "day-groups") { @elections.group_by(&:election_date).each { |date, elections| day_group(date, elections) } }
        Pagination(pagy: @pagy, noun: "elections")
      else
        empty_state
      end
    end
  end

  private

  def elections_header
    header(class: "elections-header") do
      div(class: "elections-intro") do
        span(class: "eyebrow") { "Elections" }
        h1(class: "display-title") { "Every election" }
        p(class: "ballot-lede") { header_lede }
      end
      div(class: "place-actions") do
        PillLink(label: "Make a mock election", path: new_mock_election_path, icon: :flask_conical, variant: "outline")
        PillLink(label: "New election", path: new_election_path) if current_voter&.admin?
      end
    end
  end

  def header_lede
    "#{delimited(@tab_counts["upcoming"])} #{"election".pluralize(@tab_counts["upcoming"])} open for mountains, " \
      "#{delimited(@tab_counts["past"])} finished, and #{delimited(@tab_counts["mock"])} mock #{"election".pluralize(@tab_counts["mock"])} to practice on."
  end

  # The open elections where the voter lives, pulled out of the long list.
  def your_elections
    return unless lives_somewhere? && !@filters[:near]

    elections = Election.real.open_to_rating.in_jurisdictions(current_voter.ballot_jurisdictions).soonest_first.includes(:races).limit(4).to_a
    return if elections.empty?

    section(class: "your-elections", aria: { label: "Your elections" }) do
      div(class: "your-elections-head") do
        span(class: "eyebrow") do
          icon(:map_pin)
          plain "Where you live"
        end
        link_to listing_path(near: true), class: "text-link" do
          plain "Show only these"
          icon(:chevron_right)
        end
      end
      div(class: "your-election-grid") { elections.each { your_election_card(it) } }
    end
  end

  def your_election_card(election)
    link_to election, class: "your-election-card" do
      span(class: "your-election-date") { election.election_date.strftime("%a %b %-d") }
      strong(class: "your-election-name") { election.name }
      span(class: "your-election-meta") { your_election_meta(election) }
    end
  end

  def your_election_meta(election)
    saved = election.races.count { progress_for_your_elections[it.id] == "saved" }
    "#{saved} of #{pluralize(election.races.size, "seat")} saved"
  end

  def progress_for_your_elections
    @progress_for_your_elections ||= current_voter.mountain_progress(Race.joins(:election).merge(Election.real.open_to_rating)
      .in_jurisdictions(current_voter.ballot_jurisdictions))
  end

  def listing_tabs
    nav(class: "listing-tabs", aria: { label: "Which elections" }) do
      Election::LISTING_TABS.each do |tab|
        current = tab == @filters[:tab]
        link_to listing_path(tab: tab), class: "listing-tab#{" is-current" if current}", aria: { current: (current ? "page" : nil) } do
          span(class: "listing-tab-label") { TAB_LABELS.fetch(tab) }
          span(class: "listing-tab-count") { delimited(@tab_counts.fetch(tab)) }
        end
      end
    end
  end

  def listing_filters
    div(class: "listing-filters") do
      form(action: elections_path, method: "get", role: "search", class: "listing-search") do
        input(type: "hidden", name: "tab", value: @filters[:tab])
        input(type: "hidden", name: "kind", value: @filters[:kind]) if @filters[:kind]
        input(type: "hidden", name: "near", value: "1") if @filters[:near]
        label(for: "election-search", class: "visually-hidden") { "Search elections by name or place" }
        input(id: "election-search", type: "search", name: "q", value: @filters[:q], placeholder: "Search by name or place", class: "listing-search-input")
        button(type: "submit", class: "pill-button") { "Search" }
      end
      div(class: "filter-chips", role: "group", aria: { label: "Kind of election" }) do
        filter_chip("Any kind", listing_path(kind: nil), @filters[:kind].nil?)
        KIND_LABELS.each { |kind, label| filter_chip(label, listing_path(kind: kind), @filters[:kind] == kind) }
        near_chip if lives_somewhere?
      end
    end
  end

  def filter_chip(label, path, current)
    link_to label, path, class: "filter-chip#{" is-current" if current}", aria: { current: (current ? "true" : nil) }
  end

  def near_chip
    link_to listing_path(near: !@filters[:near]), class: "filter-chip filter-chip-near#{" is-current" if @filters[:near]}",
      aria: { pressed: @filters[:near].to_s } do
      icon(:map_pin)
      plain "Where I live"
    end
  end

  # The current filters with some changed, dropping the ones that are off.
  def listing_path(**changes)
    params = @filters.merge(changes)
    elections_path(tab: params[:tab], kind: params[:kind], q: params[:q], near: ("1" if params[:near]))
  end

  def day_group(date, elections)
    li(class: "day-group") do
      header(class: "day-header") do
        div(class: "day-stub") do
          span(class: "day-stub-day") { date.strftime("%-d") }
          span(class: "day-stub-month") { date.strftime("%b") }
        end
        div(class: "day-header-text") do
          h2(class: "day-header-title") { date.strftime("%A, %B %-d, %Y") }
          span(class: "day-header-meta") { day_meta(date) }
        end
      end
      ul(class: "election-rows") { elections.each { election_row(it) } }
    end
  end

  def day_meta(date)
    count = @day_counts.fetch(date, 0)
    "#{delimited(count)} #{"election".pluralize(count)} · #{relative_days(date)}"
  end

  def election_row(election)
    li(class: "election-row#{" is-yours" if yours?(election)}") do
      div(class: "election-row-main") do
        link_to election.name, election, class: "election-row-name"
        span(class: "election-row-place") { [ election.jurisdiction.name, election.kind&.humanize ].compact.join(" · ") }
        span(class: "election-row-ballot") { ballot_preview(election) }
      end
      div(class: "election-row-badges") { badges(election) }
    end
  end

  def ballot_preview(election)
    titles = election.races.map { it.office.position.title }.uniq
    return "No races yet" if titles.empty?

    shown = titles.first(BALLOT_PREVIEW_LIMIT).join(", ")
    shown += ", and #{titles.size - BALLOT_PREVIEW_LIMIT} more" if titles.size > BALLOT_PREVIEW_LIMIT
    "#{shown} · #{pluralize(election.races.size, "seat")}"
  end

  def badges(election)
    span(class: "row-badge row-badge-#{election.mode}") { election.mode == "mock" ? "Mock" : "Historical" } unless election.mode == "real"
    span(class: "row-badge row-badge-yours") { "Your ballot" } if yours?(election)
    progress_badge(election)
    span(class: "row-badge row-badge-following") { "Following" } if engagements.marked?(election, :follow)
    StatusChip(status: election.status) unless election.open_to_rating?
  end

  def progress_badge(election)
    saved = election.races.count { progress[it.id] == "saved" }
    return if saved.zero?

    span(class: "row-badge row-badge-saved") { "#{saved} of #{election.races.size} saved" }
  end

  def yours?(election)
    resident_jurisdiction_ids.include?(election.jurisdiction_id)
  end

  def lives_somewhere?
    return @lives_somewhere if defined?(@lives_somewhere)

    @lives_somewhere = current_voter&.current_residences&.any? || false
  end

  def resident_jurisdiction_ids
    @resident_jurisdiction_ids ||= lives_somewhere? ? current_voter.ballot_jurisdictions.pluck(:id).to_set : Set.new
  end

  def progress
    @progress ||= current_voter ? current_voter.mountain_progress(Race.where(election_id: @elections.map(&:id))) : {}
  end

  def engagements
    @engagements ||= EngagementSummary.new(@elections.to_a, current_voter)
  end

  def empty_state
    section(class: "ballot-empty") do
      h2(class: "card-title") { "No elections match" }
      p { "Try another tab, clear the kind, or search for a different place." }
      PillLink(label: "Clear filters", path: elections_path(tab: @filters[:tab]))
    end
  end
end

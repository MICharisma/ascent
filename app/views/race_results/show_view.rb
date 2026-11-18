# frozen_string_literal: true

# What a race's saved mountains add up to, for residents or for visitors: totals only, never named voters.
# The approval tally, charted and then tabled, sits beside the first-choice count the same mountains give.
class Views::RaceResults::ShowView < Views::ApplicationView
  GROUP_LABELS = { "resident" => "Residents", "visitor" => "Pretend voters" }.freeze

  prop :race, Race
  prop :group, String
  prop :summary, Hash

  def view_template
    div(class: "results-page") do
      results_strip
      div(class: "results-body") do
        results_header
        if @summary[:any_mountains]
          stat_tiles
          div(class: "results-columns") do
            tally
            two_methods
          end
          off_ballot
        else
          no_mountains
        end
        privacy_note
      end
    end
  end

  private

  def place
    @race.office.jurisdiction.name
  end

  def candidacies
    @candidacies ||= @race.candidacies.includes(:citizen).index_by(&:id)
  end

  def results_strip
    ModeBanner(mode: "results", label: "Ascent results",
      text: "Mountains built by #{place} #{@group == "resident" ? "residents" : "visitors"}. Not a poll, and not the official count.") do
      span(class: "mode-strip-note") { "Updates hourly" }
    end
  end

  def results_header
    section(class: "results-header") do
      div(class: "results-heading") do
        div do
          span(class: "eyebrow") { "Location" }
          Breadcrumb(trail: location_trail + [ [ @race.election.name, @race.election ] ], label: "Location breadcrumb")
        end
        div do
          span(class: "eyebrow") { "Jurisdiction" }
          Breadcrumb(trail: governance_trail, current: "Results", label: "Jurisdiction breadcrumb")
        end
        h1(class: "display-title") { "What #{place} approves" }
      end
      nav(class: "group-toggle", aria: { label: "Whose mountains" }) do
        RaceResults::GROUPS.each do |group|
          link_to GROUP_LABELS.fetch(group), race_results_path(@race, group: group),
            class: "group-toggle-link#{" is-current" if group == @group}", aria: { current: (group == @group ? "page" : nil) }
        end
      end
    end
  end

  def jurisdictions
    @jurisdictions ||= begin
      chain = []
      jurisdiction = @race.election.jurisdiction
      while jurisdiction
        chain.unshift(jurisdiction)
        jurisdiction = jurisdiction.parent
      end
      chain
    end
  end

  def location_trail
    @location_trail ||= begin
      location = jurisdictions.reverse.find { it.jurisdictionable_type != "District" }&.jurisdictionable
      districts = jurisdictions.reverse.take_while { it.jurisdictionable_type == "District" }.reverse.map(&:jurisdictionable)
      places = (location ? location.build_hierarchy_chain : []) + districts
      places.map { [ it.name, it ] }
    end
  end

  def governance_trail
    office = @race.office
    governance_type = office.governing_body&.governance_type
    trail = governance_type ? [ [ governance_type.name, governance_type ] ] : []
    trail + [ [ office.position.title, office.position ], [ office.name, office ], [ @race.name, @race ] ]
  end

  def stat_tiles
    div(class: "stat-tiles") do
      StatTile(value: delimited(@summary[:mountain_count]), label: "#{GROUP_LABELS.fetch(@group).downcase} built a mountain for this race")
      StatTile(value: @summary[:average_approvals].to_s, label: "candidates approved per mountain, on average")
      StatTile(value: percent(@summary[:multiple_approval_share]), label: "approved more than one candidate")
      StatTile(value: @summary[:median_baseline].to_s, label: "median baseline", modifier: "baseline")
    end
  end

  def tally
    section(class: "results-card results-tally") do
      h2(class: "card-title") { "Approval tally" }
      approval_chart
      table(class: "results-table") do
        thead do
          tr do
            th(scope: "col") { "#" }
            th(scope: "col") { "Candidate" }
            th(scope: "col", class: "numeric") { "Approved by" }
            th(scope: "col", class: "numeric") { "First choice of" }
          end
        end
        tbody do
          ranked_by(:approval_shares).each_with_index do |(candidacy_id, share), index|
            tr(class: ("is-leader" if index.zero?)) do
              td(class: "rank") { (index + 1).to_s }
              td { candidacies.fetch(candidacy_id).citizen.display_name }
              td(class: "numeric strong") { percent(share) }
              td(class: "numeric") { percent(@summary[:first_choice_shares].fetch(candidacy_id, 0)) }
            end
          end
        end
      end
    end
  end

  def approval_chart
    ranked = ranked_by :approval_shares
    Chart(options: approval_chart_options(ranked), rows: ranked.size, modifier: "bars",
      label: "Approval tally: percent of mountains approving each candidate")
  end

  def approval_chart_options(ranked)
    {
      grid: { left: 8, right: 64, top: 4, bottom: 4, containLabel: true },
      xAxis: { type: "value", max: 100, show: false },
      yAxis: { type: "category", inverse: true, axisLine: { show: false },
               data: ranked.map { candidacies.fetch(it.first).citizen.display_name } },
      series: [ { type: "bar", name: "Approved by", barMaxWidth: 26, data: ranked.map(&:last),
                  label: { show: true, position: "right", formatter: "{c}%", fontWeight: 600 } } ]
    }
  end

  def two_methods
    approval_leader = ranked_by(:approval_shares).first&.first
    plurality_leader = ranked_by(:first_choice_shares).first&.first
    section(class: "results-card results-methods") do
      h2(class: "card-title") { "Same mountains, two methods" }
      p(class: "card-text") { methods_text(approval_leader, plurality_leader) }
    end
  end

  def methods_text(approval_leader, plurality_leader)
    return "No one has been approved yet." unless approval_leader && plurality_leader

    approval_name = candidacies.fetch(approval_leader).citizen.display_family_name
    plurality_name = candidacies.fetch(plurality_leader).citizen.display_family_name
    if approval_leader == plurality_leader
      "#{approval_name} leads either way: the most approved, and the most often rated highest."
    else
      "Count only each mountain's highest-rated candidate and #{plurality_name} leads. " \
        "Count every approval and #{approval_name}, accepted by more voters, leads instead."
    end
  end

  def off_ballot
    off = @summary[:off_ballot]
    return if off[:mountain_count].zero?

    section(class: "results-card results-off-ballot") do
      h2(class: "card-title") { "Off the ballot" }
      p(class: "card-text") { "Among #{delimited(off[:mountain_count])} who chose to show candidates from the primaries." }
      table(class: "results-table") do
        tbody do
          off[:approval_shares].sort_by { -it.last }.each do |candidacy_id, share|
            tr do
              td { candidacies.fetch(candidacy_id).citizen.display_name }
              td(class: "numeric strong") { percent(share) }
            end
          end
        end
      end
    end
  end

  def no_mountains
    section(class: "results-card results-withheld") do
      h2(class: "card-title") { "No mountains yet" }
      p(class: "card-text") { "Results appear as soon as someone saves a mountain for this race." }
      PillLink(label: "Build your mountain", path: edit_mountain_path(@race))
    end
  end

  def privacy_note
    section(class: "privacy-note") do
      icon(:lock)
      p do
        strong { "Totals only. " }
        plain "Ascent never shows who rated a candidate or how. Citizens who build mountains choose to take part, " \
          "so these results describe them, not the whole electorate."
      end
    end
  end

  def ranked_by(key)
    @summary[key].sort_by { -it.last }
  end
end

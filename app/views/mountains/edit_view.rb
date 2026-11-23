# frozen_string_literal: true

# The mountain: rate every candidate, set the baseline, and see who that approves. Edits autosave to a
# server draft; the save bar publishes or discards them.
class Views::Mountains::EditView < Views::ApplicationView
  def initialize(race:, voter:, mountain:, mountain_data:)
    @race = race
    @voter = voter
    @mountain = mountain
    @mountain_data = mountain_data
  end

  def view_template
    div(class: "mountain-page", data: editor_data) do
      ModeStrip(race: @race, voter: @voter) unless pretend_vote?
      div(class: "mountain-page-body") do
        race_header
        div(class: "mountain-layout") do
          section(class: "mountain-panel", aria: { label: "Your mountain" }) do
            mountain_toolbar
            @mountain_data.empty? ? render_empty_state : mountain_form
            div(class: "mountain-footer") do
              button(type: "button", class: "pill-button pill-button-outline party-endorsements-toggle", aria: { pressed: "false" },
                data: { action: "mountain-editor#togglePartyEndorsements" }) { "Party endorsements" }
            end
          end
          aside(class: "mountain-aside", aria: { label: "Your vote" }) do
            Views::Mountains::SaveBar(mountain: @mountain)
            Views::Mountains::Sharing(mountain: @mountain) if @voter == current_voter
            Views::Mountains::YourVote(mountain: @mountain)
            Views::Mountains::BaselineCard(mountain: @mountain)
            Views::Mountains::OfficialResults(race: @race) if @race.official_results_revealed_to?(@voter)
            rating_explainer
          end
        end
      end
    end
  end

  private

  def pretend_vote?
    @race.mode_for(@voter) == "pretend"
  end

  def editor_data
    {
      controller: "mountain-editor",
      analytics_race_id: @race.id,
      analytics_race_mode: @race.mode_for(@voter),
      view: "mountain",
      party_endorsements: "false",
      "mountain-editor-max-height-value": Views::Mountains.max_height,
      "mountain-editor-draft-url-value": draft_mountain_path(@race, voter_id: @voter.id)
    }
  end

  def race_header
    section(class: "race-header") do
      div(class: "race-header-text") do
        Breadcrumb(trail: [ [ "My ballot", ballot_path ], [ @race.office.jurisdiction.name ] ], current: @race.office.position.title)
        h1(class: "display-title race-title") { @race.office.name }
        div(class: "race-meta") do
          span { @race.election.name }
          span(class: "race-meta-dot", aria: { hidden: true }) { "·" }
          span { "#{pluralize(@mountain.ballot_candidacies_count, "candidate")} on the ballot" }
          StatusChip(status: @race.status)
        end
        p(class: "voter-on-behalf") { "Voter: #{@voter.name}" } unless @voter == current_voter
      end
      div(class: "mountain-header-side") do
        ModeStrip(race: @race, voter: @voter) if pretend_vote?
        div(class: "race-header-actions") do
          follow_button if current_voter
          PillLink(label: "Results", path: race_results_path(@race), icon: :chart_column, variant: "outline")
        end
      end
    end
  end

  def follow_button
    following = current_voter.engagements.follow.find_by(engageable: @race)
    if following
      button_to engagement_path(following), method: :delete, class: "pill-button pill-button-outline is-following", form_class: "inline-form" do
        icon(:bell_ring)
        plain "Following"
      end
    else
      button_to engagements_path, params: { engageable_type: "Race", engageable_id: @race.id, kind: "follow" },
        class: "pill-button pill-button-outline", form_class: "inline-form" do
        icon(:bell)
        plain "Follow race"
      end
    end
  end

  def mountain_toolbar
    div(class: "mountain-toolbar") do
      div(class: "view-toggle", role: "group", aria: { label: "View" }) do
        view_button("mountain", "Mountain", :mountain)
        view_button("list", "List", :list)
      end
      render_primary_candidates_toggle
      div(class: "mountain-legend") do
        span(class: "legend-item legend-approved") { "Lime = approved" }
        span(class: "legend-item legend-off-ballot") { "Dashed = off the ballot" }
      end
    end
  end

  def view_button(view, label, icon_name)
    button(type: "button", class: "view-toggle-button", aria: { pressed: (view == "mountain").to_s },
      data: { action: "mountain-editor#showView", "mountain-editor-view-param": view, view_button: view }) do
      icon(icon_name)
      plain label
    end
  end

  # Candidates the primaries eliminated stay off the mountain until the voter includes them.
  def render_primary_candidates_toggle
    count = @race.candidacies.from_primaries.active.count
    return if count.zero?

    included = @voter.includes_primary_candidates?(@race)
    div(class: "primary-candidates-toggle") do
      p(class: "primary-candidates-note") do
        "#{pluralize(count, "candidate")} ran in this office's primaries but #{count == 1 ? "is" : "are"} not on the general ballot."
      end
      button_to(included ? "Remove primary candidates" : "Include primary candidates",
                primary_candidates_mountain_path(@race),
                method: :patch,
                params: { voter_id: @voter.id, included: included ? "0" : "1" },
                class: "pill-button pill-button-outline")
    end
  end

  def mountain_form
    form_with(url: mountain_path(@race, voter_id: @voter.id), method: :patch, class: "mountain-form",
      data: { "mountain-editor-target": "form", action: "submit->mountain-editor#preventSubmit" }) do
      render_baseline_input
      render_rating_inputs
      div(class: "mountain-view mountain-view-chart") do
        MountainChart(race: @race, voter: @voter, baseline: @mountain.baseline, mountain_data: @mountain_data, editable: true)
      end
      div(class: "mountain-view mountain-view-list") do
        Views::Mountains::ListView(mountain_data: @mountain_data, baseline: @mountain.baseline)
      end
      p(class: "keyboard-hint") do
        "Drag in a column to rate, and drag the baseline to set who you approve. In the list, Tab to a slider and use the arrow keys."
      end
    end
  end

  def rating_explainer
    section(class: "rating-explainer") do
      h2(class: "card-heading") { "Rating is not voting" }
      ol(class: "rating-steps") do
        li { "Rate each candidate from 0 to 500. Ratings say how much you like them." }
        li { "Set your baseline. It turns ratings into a vote." }
        li { "Everyone above it is approved. Approving several is normal." }
      end
      link_to race_results_path(@race), class: "text-link" do
        plain "See what #{@race.office.jurisdiction.name} approves"
        icon(:chevron_right)
      end
    end
  end

  def render_empty_state
    div(class: "mountain-empty") do
      p { "No candidates yet for this race." }
      div(class: "mountain-empty-actions") do
        if can_simulate_mountains? && @race.mock?
          link_to simulate_mountain_path(@race), data: { turbo_method: :post }, class: "resource-action resource-action-simulate" do
            Ui::ActionIcon(kind: :simulate)
            span { "Simulate Data" }
          end
        end
        link_to("Back to Race", @race, class: "btn-tertiary")
      end
    end
  end

  def render_baseline_input
    input(type: "hidden", name: "baseline", value: @mountain.baseline, data: { "mountain-editor-target": "baselineInput" })
  end

  def render_rating_inputs
    @mountain_data.each do |data|
      input(type: "hidden", id: rating_input_id(data[:candidacy].id), name: "ratings[#{data[:candidacy].id}]",
        value: data[:has_rating] ? data[:rating_value] : nil)
    end
  end

  def rating_input_id(candidacy_id)
    "rating-input-#{candidacy_id}"
  end
end

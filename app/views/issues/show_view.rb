# frozen_string_literal: true

# An issue's page: the ways to address it, each with how many candidates take it and how many laws put it
# in place, then the candidates' stances on the issue.
class Views::Issues::ShowView < Views::ApplicationView
  prop :issue, Issue

  def view_template
    div(class: "record-page policy-page", id: dom_id(@issue, :show)) do
      PageHeader(title: @issue.title, trail: trail_for(@issue), eyebrow: "Issue · #{@issue.topic.title}", lede: lede, record: @issue)
      PolicyPath(issue: @issue, current: :issue)
      div(class: "place-layout") do
        div(class: "place-main") do
          approaches_section
          stances_section
        end
        aside(class: "place-aside", aria: { label: "Around this issue" }) do
          other_issues
          admin_card
        end
      end
    end
  end

  private

  def approaches
    @approaches ||= @issue.approaches.order(:title).to_a
  end

  def stance_counts
    @stance_counts ||= Stance.where(approach: approaches).group(:approach_id).count
  end

  def policy_counts
    @policy_counts ||= Policy.where(approach: approaches).group(:approach_id).count
  end

  def lede
    @issue.description.presence || "#{pluralize(approaches.size, "approach", plural: "approaches")} to this issue."
  end

  def approaches_section
    section(class: "place-section", id: "issue-approaches") do
      section_heading("Ways to address it", pluralize(approaches.size, "approach", plural: "approaches"))
      if approaches.any?
        ul(class: "list-rows", data: { controller: "reveal" }) { approaches.each { approach_row(it) } }
      else
        p(class: "card-text") { "No approaches are recorded for this issue yet." }
      end
    end
  end

  def approach_row(approach)
    candidates = stance_counts.fetch(approach.id, 0)
    laws = policy_counts.fetch(approach.id, 0)
    ListRow(record: approach, title: approach.title, meta: "#{pluralize(candidates, "candidate")} · #{pluralize(laws, "law")}",
      detail: approach.description.presence)
  end

  def stances_section
    stances = Stance.where(approach: approaches).includes(:approach, :stance_evidences, candidacy: [ :citizen, { race: { office: :position } } ]).to_a
    RelatedList(heading: "Candidates on this issue", records: stances, total: stances.size) { |stance| StanceRow(stance: stance) }
  end

  def other_issues
    others = @issue.topic.issues.where.not(id: @issue.id).order(:title).to_a
    return if others.empty?

    SideCard(heading: "More in #{@issue.topic.title}") do
      ul(class: "nearby-list") { others.each { |other| li { link_to other.title, other, class: "text-link" } } }
    end
  end

  def admin_card
    return unless current_voter&.admin?

    SideCard(heading: "Admin", modifier: "admin-card") do
      Ui::ResourceActions(resource: @issue)
      scaffold_new_resource_link "Add an approach", new_approach_path, record: Approach
    end
  end
end

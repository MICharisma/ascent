# frozen_string_literal: true

# A topic's page: the issues within it, each with the ways to address it, then the candidates who have
# taken a stance on any of them and the laws that put those approaches in place.
class Views::Topics::ShowView < Views::ApplicationView
  STANCE_LIMIT = 8

  prop :topic, Topic

  def view_template
    div(class: "record-page policy-page", id: dom_id(@topic, :show)) do
      PageHeader(title: @topic.title, trail: trail_for(@topic), eyebrow: "Topic", lede: lede, record: @topic, icon_for: @topic)
      PolicyPath(topic: @topic, current: :topic)
      div(class: "place-layout") do
        div(class: "place-main") do
          issues_section
          stances_section
          policies_section
        end
        aside(class: "place-aside", aria: { label: "Other topics" }) do
          other_topics
          admin_card
        end
      end
    end
  end

  private

  def issues
    @issues ||= @topic.issues.includes(:approaches).order(:title).to_a
  end

  def approach_ids
    issues.flat_map { it.approaches.map(&:id) }
  end

  def lede
    @topic.description.presence ||
      "#{pluralize(issues.size, "issue")} and #{pluralize(approach_ids.size, "approach", plural: "approaches")} to them."
  end

  def issues_section
    section(class: "place-section", id: "topic-issues") do
      section_heading("Issues", pluralize(issues.size, "issue"))
      if issues.any?
        div(class: "issue-cards") { issues.each { issue_card(it) } }
      else
        p(class: "card-text") { "No issues are recorded under this topic yet." }
      end
    end
  end

  def issue_card(issue)
    article(class: "issue-card") do
      h3(class: "issue-card-title") { link_to issue.title, issue, class: "place-race-link" }
      p(class: "card-text") { issue.description } if issue.description.present?
      if issue.approaches.any?
        ul(class: "issue-card-approaches") do
          issue.approaches.sort_by(&:title).each do |approach|
            li do
              icon(:route)
              link_to approach.title, approach, class: "text-link"
            end
          end
        end
      end
    end
  end

  def stances
    @stances ||= Stance.where(approach_id: approach_ids).includes(:approach, :stance_evidences, candidacy: [ :citizen, { race: { office: :position } } ]).to_a
  end

  def stances_section
    RelatedList(heading: "Candidates on this topic", records: stances.first(STANCE_LIMIT), total: stances.size, see_all: stances_path,
      noun: "stances") { |stance| StanceRow(stance: stance) }
  end

  def policies_section
    policies = Policy.where(approach_id: approach_ids).includes(:governing_body).order(:title).to_a
    RelatedList(heading: "Laws on this topic", records: policies, total: policies.size) do |policy|
      ListRow(record: policy, title: policy.title, meta: [ policy.governing_body&.name, policy.enacted_date&.year ].compact.join(" · ")) do
        StatusChip(status: policy.status)
      end
    end
  end

  def other_topics
    others = Topic.where.not(id: @topic.id).order(:title).to_a
    return if others.empty?

    SideCard(heading: "Other topics") do
      ul(class: "nearby-list") { others.each { |other| li { link_to other.title, other, class: "text-link" } } }
    end
  end

  def admin_card
    return unless current_voter&.admin?

    SideCard(heading: "Admin", modifier: "admin-card") do
      Ui::ResourceActions(resource: @topic)
      scaffold_new_resource_link "Add an issue", new_issue_path, record: Issue
    end
  end
end

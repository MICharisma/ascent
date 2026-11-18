# frozen_string_literal: true

# An approach's page: the candidates who take it, with how much it matters to them, and the laws that put
# it in place, so a voter can compare a promise with what has been done.
class Views::Approaches::ShowView < Views::ApplicationView
  prop :approach, Approach

  def view_template
    div(class: "record-page policy-page", id: dom_id(@approach, :show)) do
      PageHeader(title: @approach.title, trail: trail_for(@approach), eyebrow: "Approach · #{@approach.issue.title}", lede: lede,
        record: @approach, icon_for: @approach)
      PolicyPath(approach: @approach, current: :approach)
      div(class: "place-layout") do
        div(class: "place-main") do
          stances_section
          policies_section
        end
        aside(class: "place-aside", aria: { label: "Around this approach" }) do
          other_approaches
          admin_card
        end
      end
    end
  end

  private

  def stances
    @stances ||= @approach.stances.includes(:stance_evidences, candidacy: [ :citizen, { race: [ :election, { office: :position } ] } ]).to_a
  end

  def policies
    @policies ||= Policy.where(approach: @approach).includes(:governing_body).order(:title).to_a
  end

  def lede
    @approach.description.presence ||
      "#{pluralize(stances.size, "candidate")} take this approach to #{@approach.issue.title}, and #{pluralize(policies.size, "law")} put it in place."
  end

  def stances_section
    RelatedList(heading: "Candidates who take it", records: stances, total: stances.size, id: "approach-stances",
      empty: "No candidate has taken this approach yet.") do |stance|
      race = stance.candidacy.race
      StanceRow(stance: stance, meta: "#{race.office.name} · #{race.election.election_date.strftime("%b %-d, %Y")}", detail: stance.explanation.presence)
    end
  end

  def policies_section
    RelatedList(heading: "Laws that put it in place", records: policies, total: policies.size, id: "approach-policies",
      empty: "No law on Ascent puts this approach in place yet.") do |policy|
      ListRow(record: policy, title: policy.title, meta: [ policy.governing_body&.name, policy.enacted_date&.year ].compact.join(" · ")) do
        StatusChip(status: policy.status)
      end
    end
  end

  def other_approaches
    others = @approach.issue.approaches.where.not(id: @approach.id).order(:title).to_a
    return if others.empty?

    SideCard(heading: "Other ways to address #{@approach.issue.title}") do
      ul(class: "nearby-list") { others.each { |other| li { link_to other.title, other, class: "text-link" } } }
    end
  end

  def admin_card
    return unless current_voter&.admin?

    SideCard(heading: "Admin", modifier: "admin-card") { Ui::ResourceActions(resource: @approach) }
  end
end

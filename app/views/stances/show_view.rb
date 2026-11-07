# frozen_string_literal: true

# A stance's page: a candidate's position on one approach, in their words, with the evidence for it and
# the path back to the issue it addresses. The side column places the candidacy and their other stances.
class Views::Stances::ShowView < Views::ApplicationView
  prop :stance, Stance

  def view_template
    div(class: "record-page policy-page", id: dom_id(@stance, :show)) do
      PageHeader(title: "#{citizen.full_name} on #{@stance.approach.title}", trail: trail_for(@stance), current: citizen.full_name,
        eyebrow: eyebrow, lede: @stance.explanation.presence, record: @stance) do
        PillLink(label: "Their candidacy", path: candidacy_path(candidacy), icon: :badge_check, variant: "outline")
      end
      PolicyPath(approach: @stance.approach, current: :position)
      div(class: "place-layout") do
        div(class: "place-main") do
          approach_section
          evidence_section
        end
        aside(class: "place-aside", aria: { label: "About this candidate" }) do
          candidacy_card
          other_stances
          admin_card
        end
      end
    end
  end

  private

  def candidacy
    @stance.candidacy
  end

  def citizen
    candidacy.citizen
  end

  def eyebrow
    [ "Stance", ("#{@stance.priority_level.capitalize} priority" if @stance.priority_level.present?) ].compact.join(" · ")
  end

  def approach_section
    approach = @stance.approach
    section(class: "place-section") do
      section_heading("The approach")
      h3(class: "issue-card-title") { link_to approach.title, approach, class: "place-race-link" }
      p(class: "card-text") { approach.description } if approach.description.present?
      link_to approach_path(approach, anchor: "approach-stances"), class: "text-link" do
        plain "Everyone who takes it"
        icon(:chevron_right)
      end
    end
  end

  def evidence
    @evidence ||= @stance.stance_evidences.includes(communication: :channel).to_a
  end

  def legacy_links
    @stance.evidence_links.to_s.split(/[,\s]+/).grep(Communication::WEB_ADDRESS)
  end

  def evidence_section
    section(class: "place-section", id: "stance-evidence") do
      section_heading("Evidence", (pluralize(evidence.size + legacy_links.size, "source") if evidence.any? || legacy_links.any?))
      if evidence.empty? && legacy_links.empty?
        p(class: "card-text") { "No evidence is recorded for this stance yet." }
      else
        ul(class: "communication-list") do
          evidence.each { evidence_item(it) }
          legacy_links.each { legacy_item(it) }
        end
      end
    end
  end

  def evidence_item(item)
    communication = item.communication
    li(class: "communication-item") do
      a(href: communication.url, class: "text-link communication-link", target: "_blank", rel: "noopener") do
        plain communication.name
        icon(:external_link)
      end
      blockquote(class: "evidence-quote") { item.quote } if item.quote.present?
      span(class: "communication-meta") do
        [ item.relation.capitalize, communication.kind.humanize, communication.published_on.strftime("%b %-d, %Y"), (item.timestamp && "at #{item.timestamp}") ]
          .compact.join(" · ")
      end
    end
  end

  def legacy_item(url)
    li(class: "communication-item") do
      a(href: url, class: "text-link communication-link", target: "_blank", rel: "noopener") do
        plain URI(url).host.to_s.delete_prefix("www.")
        icon(:external_link)
      end
      span(class: "communication-meta") { url }
    end
  end

  def candidacy_card
    race = candidacy.race
    SideCard(heading: "The candidacy") do
      dl(class: "place-facts-list") do
        FactRow(label: "Candidate") { link_to citizen.full_name, citizen, class: "text-link" }
        FactRow(label: "Running for") { link_to race.office.name, race, class: "text-link" }
        FactRow(label: "Election") { link_to race.election.name, race.election, class: "text-link" }
      end
    end
  end

  def other_stances
    others = candidacy.stances.where.not(id: @stance.id).includes(:approach).to_a
    return if others.empty?

    SideCard(heading: "Their other stances") do
      ul(class: "nearby-list") { others.each { |other| li { link_to other.approach.title, other, class: "text-link" } } }
    end
  end

  def admin_card
    return unless current_voter&.admin?

    SideCard(heading: "Admin", modifier: "admin-card") { Ui::ResourceActions(resource: @stance) }
  end
end

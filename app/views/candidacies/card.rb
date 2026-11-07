# frozen_string_literal: true

# The card a ballot opens on a candidate's name: who they are, their major endorsements, how residents'
# mountains treat them, and links to their citizen and candidacy pages.
# Rendered into the Turbo frame of the same id; links leave the frame for the whole page.
class Views::Candidacies::Card < Views::ApplicationView
  ENDORSEMENT_LIMIT = 5

  prop :candidacy, Candidacy

  def view_template
    turbo_frame_tag(dom_id(@candidacy, :card), target: "_top") do
      article(class: "candidate-card", aria: { label: citizen.full_name }) do
        card_head
        ballot_lines
        endorsements_section
        support_section
        card_links
      end
    end
  end

  private

  def citizen
    @candidacy.citizen
  end

  def card_head
    header(class: "candidate-card-head") do
      div(class: "candidate-card-title") do
        h3(class: "candidate-card-name") { CitizenName(citizen: citizen) }
        span(class: "candidate-card-office") { @candidacy.race.office.name }
      end
      button(type: "button", class: "icon-action candidate-card-close", popovertarget: candidate_popover_id(@candidacy),
        popovertargetaction: "hide", aria: { label: "Close" }) { icon(:x) }
    end
  end

  # Party lines already appear as endorsements, so only other designations show here.
  def ballot_lines
    labels = @candidacy.ballot_lines.reject(&:party_id).map(&:label)
    labels = [ @candidacy.primary_summary ] if labels.empty? && @candidacy.primary_candidacy
    return if labels.empty?

    ul(class: "chip-list candidate-card-lines") { labels.each { |label| li(class: "place-chip") { label } } }
  end

  def endorsements_section
    endorsements = @candidacy.endorsements.major.strongest_first.includes(:endorser).to_a
    section(class: "candidate-card-section") do
      h4(class: "card-heading") { "Major endorsements" }
      if endorsements.empty?
        p(class: "card-text") { "No endorsements recorded yet." }
      else
        ul(class: "endorsement-list") { endorsements.first(ENDORSEMENT_LIMIT).each { endorsement_item(it) } }
        p(class: "card-text") { "And #{pluralize(endorsements.size - ENDORSEMENT_LIMIT, "more")}." } if endorsements.size > ENDORSEMENT_LIMIT
      end
    end
  end

  def endorsement_item(endorsement)
    li(class: "endorsement-item") do
      strong(class: "endorsement-name") { link_to endorsement.endorser.name, endorsement.endorser, class: "text-link" }
      span(class: "endorsement-kind") { endorsement_kind(endorsement) }
    end
  end

  def endorsement_kind(endorsement)
    return "Party line" if endorsement.kind == "ballot_line"

    [ "Endorsed", endorsement.endorsed_on&.strftime("%b %Y") ].compact.join(" · ")
  end

  def support_section
    support = @candidacy.support
    section(class: "candidate-card-section") do
      h4(class: "card-heading") { "Support among residents" }
      if support[:any_mountains]
        div(class: "support-stats") do
          support_stat(percent(support[:approval_share]), "approve")
          support_stat(percent(support[:first_choice_share]), "rate them highest") if support[:first_choice_share]
          support_stat(support[:average_rating]&.to_s || "—", "average rating")
        end
        p(class: "card-text") { "From #{pluralize(support[:mountain_count], "saved mountain")}. Totals only." }
      else
        p(class: "card-text") { "No resident has saved a mountain for this race yet." }
      end
    end
  end

  def support_stat(value, label)
    div(class: "support-stat") do
      span(class: "support-stat-value") { value }
      span(class: "support-stat-label") { label }
    end
  end

  def card_links
    footer(class: "candidate-card-links") do
      PillLink(label: "Citizen page", path: citizen_path(citizen), icon: :user, variant: "outline")
      PillLink(label: "Candidacy page", path: candidacy_path(@candidacy), icon: :file_text, variant: "outline")
    end
  end
end

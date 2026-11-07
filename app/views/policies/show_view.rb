# frozen_string_literal: true

# A law's page: what it does and which approach to which issue it puts in place, the sections of code
# that carry it out, and the candidates who take the same approach.
class Views::Policies::ShowView < Views::ApplicationView
  prop :policy, Policy

  def view_template
    div(class: "record-page policy-page", id: dom_id(@policy, :show)) do
      PageHeader(title: @policy.title, trail: trail, eyebrow: eyebrow, lede: @policy.description.presence, record: @policy,
        icon_for: @policy, chips: method(:chips))
      PolicyPath(approach: @policy.approach, current: :position) if @policy.approach
      div(class: "place-layout") do
        div(class: "place-main") do
          codes_section
          stances_section
        end
        aside(class: "place-aside", aria: { label: "About this law" }) do
          facts_card
          admin_card
        end
      end
    end
  end

  private

  def body
    @policy.governing_body
  end

  def trail
    [ [ "Governing bodies", governing_bodies_path ], [ body.name, body ] ]
  end

  def eyebrow
    [ "Law", body.name ].join(" · ")
  end

  def chips
    StatusChip(status: @policy.status)
    span(class: "row-badge") { @policy.area_of_concern.name } if @policy.area_of_concern
  end

  def codes_section
    codes = @policy.official_codes.order(:code_number, :title).to_a
    RelatedList(heading: "In the code", records: codes, total: codes.size, id: "policy-codes",
      empty: "No section of code for this law is on Ascent yet.") do |code|
      ListRow(record: code, title: code.title, meta: [ code.code_number, code.effective_date && "Effective #{code.effective_date.strftime("%b %-d, %Y")}" ].compact.join(" · "),
        detail: code.summary.presence) do
        StatusChip(status: code.status) if code.status.present?
      end
    end
  end

  def stances_section
    return unless @policy.approach

    stances = @policy.approach.stances.includes(:approach, :stance_evidences, candidacy: [ :citizen, { race: { office: :position } } ]).to_a
    RelatedList(heading: "Candidates who take the same approach", records: stances, total: stances.size,
      empty: "No candidate has taken this approach yet.") { |stance| StanceRow(stance: stance) }
  end

  def facts_card
    SideCard(heading: "About this law") do
      dl(class: "place-facts-list") do
        FactRow(label: "Made by") { link_to body.name, body, class: "text-link" }
        FactRow(label: "Approach") { link_to @policy.approach.title, @policy.approach, class: "text-link" } if @policy.approach
        FactRow(label: "Area") { link_to @policy.area_of_concern.name, @policy.area_of_concern, class: "text-link" } if @policy.area_of_concern
        FactRow(label: "Enacted") { @policy.enacted_date.strftime("%b %-d, %Y") } if @policy.enacted_date
        FactRow(label: "Expires") { @policy.expiration_date.strftime("%b %-d, %Y") } if @policy.expiration_date
      end
    end
  end

  def admin_card
    return unless current_voter&.admin?

    SideCard(heading: "Admin", modifier: "admin-card") do
      Ui::ResourceActions(resource: @policy)
      scaffold_new_resource_link "Add a section of code", new_official_code_path, record: OfficialCode
    end
  end
end

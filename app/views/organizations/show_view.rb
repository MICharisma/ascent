# frozen_string_literal: true

class Views::Organizations::ShowView < Views::ApplicationView
  prop :organization, Organization

  def view_template
    div(class: "record-page", id: dom_id(@organization, :show)) do
      PageHeader(title: @organization.name, trail: trail, eyebrow: kind, record: @organization)
      div(class: "place-layout") do
        div(class: "place-main") do
          endorsements_section
          nominations_section
        end
        aside(class: "place-aside", aria: { label: "About #{@organization.name}" }) do
          SideCard(heading: "About") do
            dl(class: "place-facts-list") do
              FactRow(label: "Kind") { kind }
              FactRow(label: "Abbreviation") { @organization.abbreviation } if @organization.abbreviation.present?
              FactRow(label: "State") { link_to @organization.state.name, @organization.state, class: "text-link" } if @organization.state
            end
          end
          OfficialChannels(owners: [ @organization ])
        end
      end
    end
  end

  private

  def kind
    @organization.is_a?(Party) ? "Party" : @organization.kind.humanize
  end

  def trail
    @organization.is_a?(Party) ? [ [ "Organizations", organizations_path ], [ "Parties", parties_path ] ] : [ [ "Organizations", organizations_path ] ]
  end

  def endorsements_section
    endorsements = @organization.endorsements.current.strongest_first
    RelatedList(heading: "Current endorsements", records: endorsements.includes(candidacy: [ :citizen, { race: [ :election, { office: [ :position, { jurisdiction: :jurisdictionable } ] } ] } ]).limit(10),
      total: endorsements.count, empty: "No current endorsements are recorded.") { EndorsementRow(endorsement: it) }
    PillLink(label: "All endorsements", path: endorsements_path(organization_id: @organization.id), icon: :badge_check)
  end

  def nominations_section
    offices = @organization.nominations.includes(:position, :nominating_organization, jurisdiction: :jurisdictionable, nominee_for: [ :position, { jurisdiction: :jurisdictionable } ]).sort_by(&:name)
    RelatedList(heading: "Nominating offices", records: offices, total: offices.size,
      empty: "No nominating offices are recorded.") do |office|
      ListRow(record: office, title: office.name, meta: office.jurisdiction.name)
    end
  end
end

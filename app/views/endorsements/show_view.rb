# frozen_string_literal: true

class Views::Endorsements::ShowView < Views::ApplicationView
  prop :endorsement, Endorsement

  def view_template
    div(class: "record-page", id: dom_id(@endorsement, :show)) do
      PageHeader(title: "#{@endorsement.endorser.name} supports #{@endorsement.candidacy.citizen.name}",
        trail: [ [ "Endorsements", endorsements_path ] ], eyebrow: @endorsement.kind_label, record: @endorsement)
      SideCard(heading: "Endorsement details") do
        dl(class: "place-facts-list") do
          FactRow(label: "Endorser") { link_to @endorsement.endorser.name, @endorsement.endorser, class: "text-link" }
          FactRow(label: "Candidate") { link_to @endorsement.candidacy.name, @endorsement.candidacy, class: "text-link" }
          FactRow(label: "Election") { link_to @endorsement.candidacy.election.name, @endorsement.candidacy.election, class: "text-link" }
          FactRow(label: "Status") { @endorsement.withdrawn_on ? "Withdrawn" : "Current" }
          FactRow(label: "Endorsed") { @endorsement.endorsed_on.strftime("%b %-d, %Y") } if @endorsement.endorsed_on
          FactRow(label: "Withdrawn") { @endorsement.withdrawn_on.strftime("%b %-d, %Y") } if @endorsement.withdrawn_on
        end
        simple_format @endorsement.notes, class: "card-text" if @endorsement.notes.present?
      end
    end
  end
end

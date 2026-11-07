# frozen_string_literal: true

class Views::Components::EndorsementRow < Views::ApplicationView
  prop :endorsement, Endorsement

  def view_template
    candidacy = @endorsement.candidacy
    ListRow(record: @endorsement, title: "#{@endorsement.endorser.name} supports #{candidacy.citizen.name}",
      meta: [ @endorsement.kind_label, candidacy.race.office.name, candidacy.race.election.name, @endorsement.endorsed_on&.strftime("%b %-d, %Y") ].compact.join(" · ")) do
      span(class: "row-badge") { @endorsement.withdrawn_on ? "Withdrawn" : "Current" }
    end
  end
end

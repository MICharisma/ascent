# frozen_string_literal: true

# One candidate's stance in a list: who takes it, on what, and how much it matters to them.
#   StanceRow(stance: stance)
#   StanceRow(stance: stance, meta: "Governor - Calder · Nov 3, 2026", detail: stance.explanation)
class Views::Components::StanceRow < Views::ApplicationView
  prop :stance, Stance
  prop :meta, _Nilable(String)
  prop :detail, _Nilable(String)

  def view_template
    candidacy = @stance.candidacy
    ListRow(record: @stance, title: candidacy.citizen.full_name,
      meta: @meta || "#{@stance.approach.title} · #{candidacy.race.office.position.title}", detail: @detail) do
      span(class: "row-badge row-badge-priority") { "#{@stance.priority_level} priority" } if @stance.priority_level.present?
      span(class: "row-badge") { pluralize(@stance.stance_evidences.size, "source") } if @stance.stance_evidences.any?
    end
  end
end

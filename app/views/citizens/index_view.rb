# frozen_string_literal: true

# Everyone who has stood for office, by surname: search by name or narrow to a state, and each row names
# the citizen's latest race and how they appear on its ballot.
class Views::Citizens::IndexView < Views::ApplicationView
  prop :citizens, ActiveRecord::Relation
  prop :pagy, _Nilable(Pagy)
  prop :filters, Hash
  prop :states, ActiveRecord::Relation

  def view_template
    IndexPage(title: "Citizens", records: @citizens, pagy: @pagy, noun: "citizen", frame: "citizens-list", eyebrow: "Candidates",
      lede: "Everyone who has stood for an office on Ascent, by surname. Search for a name, or pick a state.",
      trail: [ [ "Elections", elections_path ] ], clear_path: citizens_path,
      actions: (method(:new_citizen_link) if scaffold_new_resource_visible?(Citizen)), filters: method(:filter_form)) { citizen_row(it) }
  end

  private

  def new_citizen_link
    PillLink(label: "New citizen", path: new_citizen_path, icon: :plus)
  end

  def filter_form
    FilterForm(url: citizens_path, label: "Filter citizens", placeholder: "Search by name", values: @filters, clear_path: citizens_path,
      selects: [ [ :state_id, "State", @states.map { [ it.name, it.id ] }, "All states" ] ])
  end

  def citizen_row(citizen)
    latest = citizen.candidacies.max_by { it.race.election.election_date }
    ListRow(record: citizen, title: citizen.full_name, meta: latest_meta(latest, citizen), detail: latest&.ballot_labels) do
      span(class: "row-badge row-badge-mock") { "Invented" } if citizen.fictional
    end
  end

  def latest_meta(latest, citizen)
    return "No candidacies yet" unless latest

    text = "#{latest.race.office.name} · #{latest.race.election.election_date.strftime("%b %-d, %Y")}"
    citizen.candidacies.size > 1 ? "#{text} · #{pluralize(citizen.candidacies.size - 1, "earlier race")}" : text
  end
end

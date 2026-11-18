# frozen_string_literal: true

# Every candidacy, latest election first: search by the candidate's name or narrow by status. Each row
# names the seat and how the candidate appears on its ballot, and how many voters have rated them, in total.
class Views::Candidacies::IndexView < Views::ApplicationView
  STATUSES = %w[active announced withdrawn disqualified].freeze

  prop :candidacies, ActiveRecord::Relation
  prop :pagy, _Nilable(Pagy)
  prop :filters, Hash
  prop :scope, Hash
  prop :rating_counts, Hash

  def view_template
    IndexPage(title: "Candidacies", records: @candidacies, pagy: @pagy, noun: "candidacy", frame: "candidacies-list", eyebrow: "Candidates",
      lede: "Each time someone has stood for a seat, latest election first. Search for a candidate by name.",
      trail: [ [ "Elections", elections_path ] ], clear_path: candidacies_path(@scope),
      actions: (method(:new_candidacy_link) if scaffold_new_resource_visible?(Candidacy)), filters: method(:filter_form)) { candidacy_row(it) }
  end

  private

  def new_candidacy_link
    PillLink(label: "New candidacy", path: new_candidacy_path, icon: :plus)
  end

  def filter_form
    FilterForm(url: candidacies_path, label: "Filter candidacies", placeholder: "Candidate's name", values: @filters,
      clear_path: candidacies_path(@scope), hidden: @scope, selects: [ [ :status, "Status", STATUSES.map { [ it.humanize, it ] }, "Any status" ] ])
  end

  def candidacy_row(candidacy)
    race = candidacy.race
    ListRow(record: candidacy, title: candidacy.citizen.display_name,
      meta: [ candidacy.ballot_labels, race.office.name, race.election.election_date.strftime("%b %-d, %Y") ].compact.join(" · "),
      detail: candidacy.platform_summary.presence) do
      rated = @rating_counts.fetch(candidacy.id, 0)
      span(class: "row-badge") { "#{delimited(rated)} #{"voter".pluralize(rated)} rated" } if rated.positive?
      StatusChip(status: candidacy.status.downcase)
    end
  end
end

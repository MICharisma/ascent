class Views::Engagements::IndexView < Views::ApplicationView
  SECTIONS = { "bookmark" => "Saved", "favorite" => "Favorites", "follow" => "Following", "hide" => "Hidden" }.freeze

  prop :engagements, _Enumerable(Engagements::Engagement)
  prop :summary, _Nilable(Engagements::Summary)

  def view_template
    div(class: "saved-page", id: "saved", data: { controller: "saved-patch" }) do
      h1 { "Saved" }

      if @engagements.any?
        SECTIONS.each { |kind, title| saved_section(kind, title) }
      else
        p(class: "saved-empty") { "Nothing saved yet. Candidacies, races, issues, stances, and citizens each have Save, Favorite, Follow, and Hide buttons." }
      end
    end
  end

  private

  def saved_section(kind, title)
    engagements = engagements_by_kind[kind]
    return unless engagements

    section(class: "saved-section saved-#{kind}") do
      h2 { title }

      engagements.each do |engagement|
        render Views::Engagements::SavedRow.new(record: engagement.engageable, kind: kind, summary: summary)
      end
    end
  end

  def engagements_by_kind
    @engagements_by_kind ||= @engagements.group_by(&:kind)
  end

  def summary
    @summary ||= Engagements::Summary.new(@engagements.map(&:engageable).uniq, current_voter)
  end
end

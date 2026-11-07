class Views::Engagements::IndexView < Views::ApplicationView
  SECTIONS = { "bookmark" => "Saved", "favorite" => "Favorites", "follow" => "Following", "hide" => "Hidden" }.freeze

  prop :engagements, ActiveRecord::Relation

  def view_template
    div(class: "saved-page", id: "saved") do
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

      engagements.each { saved_item(it.engageable) }
    end
  end

  def saved_item(record)
    div(class: "saved-item", id: dom_id(record, :saved)) do
      span(class: "saved-type") { record.model_name.human }
      link_to record.name, record, class: "link saved-name"
      ActionBar(record: record, summary: summary)
    end
  end

  def engagements_by_kind
    @engagements_by_kind ||= @engagements.group_by(&:kind)
  end

  def summary
    @summary ||= EngagementSummary.new(@engagements.map(&:engageable).uniq, current_voter)
  end
end

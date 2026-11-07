# frozen_string_literal: true

class Views::Mountains::SaveBar < Views::ApplicationView
  prop :mountain, Mountain

  def view_template
    div(class: "save-bar #{@mountain.unsaved? ? "is-dirty" : "is-clean"}", id: "mountain-save-bar", role: "region", tabindex: 0,
      aria: { label: "Save", live: "polite" }) do
      div(class: "save-bar-text") do
        strong(class: "save-bar-title") { bar_title }
        span(class: "save-bar-detail") { detail }
      end
      div(class: "save-bar-actions") { @mountain.unsaved? ? dirty_actions : clean_actions }
    end
  end

  private

  def voter_id
    @mountain.voter.id
  end

  def change_count
    @mountain.unsaved_changes[:candidacy_ids].size + (@mountain.unsaved_changes[:baseline] ? 1 : 0)
  end

  def bar_title
    @mountain.unsaved? ? "#{pluralize(change_count, "unsaved change")}" : "All changes saved"
  end

  def detail
    unless @mountain.unsaved?
      return @mountain.publication ? "Your saved ratings and baseline are public." : "Your ratings and baseline are private to you."
    end

    [ changed_ratings_text, changed_baseline_text ].compact.join(" · ")
  end

  def changed_ratings_text
    ids = @mountain.unsaved_changes[:candidacy_ids]
    "Ratings: #{@mountain.candidacies.where(id: ids).map { it.citizen.full_name }.join(", ")}" if ids.any?
  end

  def changed_baseline_text
    from, to = @mountain.unsaved_changes[:baseline]
    "Baseline #{from || "unset"} → #{to}" if to
  end

  def dirty_actions
    button_to "Discard", draft_mountain_path(@mountain.race, voter_id: voter_id), method: :delete,
      class: "pill-button pill-button-ghost", form_class: "inline-form"
    button_to "Save mountain", save_mountain_path(@mountain.race, voter_id: voter_id),
      class: "pill-button pill-button-summit", form_class: "inline-form",
      form: { data: { action: "submit->mountain-editor#saveAfterDraft" } }
  end

  def clean_actions
    button(type: "button", class: "pill-button pill-button-quiet", disabled: true) { "Saved" }
  end
end

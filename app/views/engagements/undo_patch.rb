# frozen_string_literal: true

class Views::Engagements::UndoPatch < Views::ApplicationView
  prop :record, ActiveRecord::Base
  prop :kind, String

  def view_template
    section_title = Views::Engagements::IndexView::SECTIONS.fetch(@kind, @kind.humanize)

    div(class: "saved-item saved-undo-patch is-entering", id: dom_id(@record, :"saved_#{@kind}"), role: "status") do
      span(class: "saved-type") { @record.model_name.human }
      p(class: "saved-undo-message") do
        plain "Removed "
        link_to @record.name, @record, class: "link saved-undo-name"
        plain " from #{section_title}."
      end
      button_to Engagements::Engine.routes.url_helpers.engagements_path,
        params: { engageable_type: @record.class.polymorphic_name, engageable_id: @record.id, kind: @kind },
        class: "saved-undo-button",
        form_class: "saved-undo-form",
        aria: { label: "Undo removing #{@record.name} from #{section_title}" } do
        icon(:undo_2)
        span { "Undo" }
      end
    end
  end
end

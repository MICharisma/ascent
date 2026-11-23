# frozen_string_literal: true

class Views::Engagements::SavedRow < Views::ApplicationView
  prop :record, ActiveRecord::Base
  prop :kind, String
  prop :summary, _Nilable(Engagements::Summary)
  prop :restoring, _Boolean, default: false

  def view_template
    classes = [ "saved-item" ]
    classes << "is-restoring" if @restoring

    div(class: classes.join(" "), id: dom_id(@record, :"saved_#{@kind}")) do
      span(class: "saved-type") { @record.model_name.human }
      link_to @record.name, @record, class: "link saved-name"
      ActionBar(record: @record, summary: @summary, bar_id: dom_id(@record, :"#{@kind}_action_bar"))
    end
  end
end

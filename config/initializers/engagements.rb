# frozen_string_literal: true

Engagements.configure do |config|
  config.engageable_types = %w[Candidacy Race Issue Stance Citizen Municipality Election]
  config.actor_resolver = ->(controller) { controller.current_voter }
  config.sign_in_path = ->(view) { view.main_app.new_voter_session_path }

  config.action_bar_renderer = ->(_view, record, summary) {
    Views::Components::ActionBar.new(record: record, summary: summary)
  }

  config.index_renderer = ->(_view, engagements:, summary:, **) {
    Views::Engagements::IndexView.new(engagements: engagements, summary: summary)
  }

  config.turbo_stream_renderer = ->(view, record:, kind:, action:, summary:) {
    row_id = view.dom_id(record, :"saved_#{kind}")
    component = if action == :destroy
      Views::Engagements::UndoPatch.new(record: record, kind: kind)
    else
      Views::Engagements::SavedRow.new(record: record, kind: kind, summary: summary, restoring: true)
    end
    view.turbo_stream.replace(row_id, view.render(component))
  }
end

Rails.application.config.to_prepare do
  Engagements::EngagementsController.class_eval do
    private

    def action_policy_target
      case action_name
      when "index", "create"
        Engagements::Engagement
      else
        params[:id] ? Engagements::Engagement.find(params[:id]) : Engagements::Engagement
      end
    end
  end
end

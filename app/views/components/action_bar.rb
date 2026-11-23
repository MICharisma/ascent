# frozen_string_literal: true

# The buttons a visitor uses on a record: save, favorite, follow, hide, and share.
# Lists pass one EngagementSummary for every row so the page loads marks and counts once.
class Views::Components::ActionBar < Views::ApplicationView
  ACTIONS = {
    bookmark: { label: "Save", marked_label: "Saved", icon_name: :bookmark, marked_icon_name: :bookmark_check },
    favorite: { label: "Favorite", marked_label: "Favorited", icon_name: :heart, marked_icon_name: :heart },
    follow: { label: "Follow", marked_label: "Following", icon_name: :bell, marked_icon_name: :bell_ring },
    hide: { label: "Hide", marked_label: "Unhide", icon_name: :eye_off, marked_icon_name: :eye }
  }.freeze

  prop :record, ActiveRecord::Base
  prop :summary, _Nilable(EngagementSummary)

  def view_template
    nav(class: "action-bar", id: dom_id(@record, :action_bar), aria: { label: "Actions for #{@record.name}" }) do
      ACTIONS.each { |kind, look| engagement_action(kind, **look) }
      share_action
    end
  end

  private

  def engagement_action(kind, label:, marked_label:, icon_name:, marked_icon_name:)
    if current_voter
      toggle_button(kind, label: label, marked_label: marked_label, icon_name: icon_name, marked_icon_name: marked_icon_name)
    else
      link_to new_voter_session_path, class: "action-button action-#{kind}", title: "Sign in to #{label.downcase}" do
        action_content(kind, label, icon_name)
      end
    end
  end

  def toggle_button(kind, label:, marked_label:, icon_name:, marked_icon_name:)
    engagement = summary.engagement(@record, kind)

    if engagement
      button_to engagement_path(engagement), method: :delete, class: "action-button action-#{kind} marked",
        form_class: "action-form", aria: { pressed: true } do
        action_content(kind, marked_label, marked_icon_name)
      end
    else
      button_to engagements_path, params: { engageable_type: @record.class.polymorphic_name, engageable_id: @record.id, kind: kind },
        class: "action-button action-#{kind}", form_class: "action-form", aria: { pressed: false } do
        action_content(kind, label, icon_name)
      end
    end
  end

  def action_content(kind, label, icon_name)
    icon(icon_name)
    span(class: "action-label") { label }
    count = summary.count(@record, kind) if Engagement::PUBLIC_KINDS.include?(kind.to_s)
    span(class: "action-count") { count.to_s } if count&.positive?
  end

  def share_action
    button(type: "button", class: "action-button action-share",
      data: { controller: "share", action: "share#share", share_url_value: polymorphic_url(@record), share_title_value: @record.name,
        share_target_type_value: @record.model_name.singular, share_target_id_value: @record.id }) do
      icon(:share_2)
      span(class: "action-label") { "Share" }
      span(class: "action-status", role: "status", data: { share_target: "status" })
    end
  end

  def summary
    @summary ||= EngagementSummary.new([ @record ], current_voter)
  end
end

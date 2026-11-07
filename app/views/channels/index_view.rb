# frozen_string_literal: true

class Views::Channels::IndexView < Views::ApplicationView
  prop :channels, ActiveRecord::Relation
  prop :pagy, _Nilable(Pagy)
  prop :review_status, _Nilable(String)

  def view_template
    IndexPage(
      title: "Channel reviews",
      records: @channels,
      pagy: @pagy,
      noun: "channel",
      frame: "channels-list",
      eyebrow: "Moderation",
      lede: "Review candidate, campaign, and organization social account links. Approved channels appear as official channels on profiles.",
      empty_title: "No channels to review",
      empty_text: "No social account links match this queue."
    ) do |channel|
      li(class: "list-row", id: dom_id(channel)) do
        div(class: "list-row-main") do
          if channel.url.present?
            a(href: channel.url, target: "_blank", rel: "nofollow noopener noreferrer", class: "list-row-title") { channel.name }
          else
            span(class: "list-row-title") { channel.name }
          end
          span(class: "list-row-meta") { owner_meta(channel) }
        end
        div(class: "list-row-badges") do
          span(class: "row-badge") { channel.review_status.capitalize }
          span(class: "row-badge") { "Official" } if channel.official?
          button_to "Approve", channel_path(channel), method: :patch, params: { review_status: "approved" }, class: "secondary" unless channel.review_status == "approved" && channel.official?
          button_to "Reject", channel_path(channel), method: :patch, params: { review_status: "rejected" }, class: "secondary" unless channel.review_status == "rejected"
        end
      end
    end
  end

  private

  def owner_meta(channel)
    parts = []
    parts << case channel.owner
    when Candidacy
      "#{channel.owner.citizen.full_name} (Candidacy)"
    when Citizen
      channel.owner.full_name
    when Organization
      channel.owner.name
    else
      "Unassigned"
    end
    parts << channel.url if channel.url.present?
    parts << "Reviewed by #{channel.reviewed_by.full_name}" if channel.reviewed_by
    parts.join(" · ")
  end
end

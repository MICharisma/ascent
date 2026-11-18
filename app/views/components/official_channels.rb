# frozen_string_literal: true

# A side card linking the official accounts a citizen or their campaigns speak through, if there are any.
#   OfficialChannels(owners: [ citizen, *citizen.candidacies ])
class Views::Components::OfficialChannels < Views::ApplicationView
  prop :owners, Array

  def view_template
    channels = Channel.official.where(owner: @owners).includes(:owner).order(:platform, :handle).to_a
      .sort_by { it.platform == "website" ? 0 : 1 }
    return if channels.empty?

    SideCard(heading: "Official channels") do
      ul(class: "profile-channel-list") do
        channels.each do |channel|
          li(class: "profile-channel") do
            channel_link(channel)
            span(class: "communication-meta") do
              case channel.owner
              when Candidacy then "Campaign · #{channel.owner.election.election_date.year}"
              when Organization then "Organization"
              else "Citizenal"
              end
            end
          end
        end
      end
    end
  end

  private

  def channel_link(channel)
    label = "#{channel.handle} · #{channel.platform_label}"
    return plain(label) if channel.url.blank?

    a(href: channel.url, class: "text-link", target: "_blank", rel: "noopener") { label }
  end
end

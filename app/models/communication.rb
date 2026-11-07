# Something a campaign published or said: a video, post, ad, speech, debate clip, interview,
# platform page, or mailer. Ascent keeps links, a short summary, and quotes, never the media itself.
class Communication < ApplicationRecord
  KINDS = %w[video post ad speech debate interview platform press_release mailer other].freeze
  AVAILABILITY = %w[available edited removed].freeze
  WEB_ADDRESS = %r{\Ahttps?://\S+\z}

  belongs_to :channel, optional: true
  has_many :communication_features, dependent: :destroy
  has_many :featured_candidacies, through: :communication_features, source: :candidacy
  has_many :stance_evidences, dependent: :restrict_with_error

  validates :kind, inclusion: { in: KINDS }
  validates :availability, inclusion: { in: AVAILABILITY }
  validates :published_on, presence: true
  validates :url, presence: true, uniqueness: true, format: { with: WEB_ADDRESS }
  validates :archived_url, format: { with: WEB_ADDRESS }, allow_blank: true
  validates :duration_seconds, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  scope :for_profile, ->(citizen, candidacies) {
    where(channel: Channel.where(owner: [ citizen, *candidacies ]))
      .or(where(id: CommunicationFeature.where(candidacy: candidacies).select(:communication_id)))
  }

  def name
    title.presence || "#{kind.humanize} published #{published_on}"
  end

  def embed_url
    return if availability == "removed"

    uri = URI.parse(url)
    case uri.host&.downcase
    when "youtube.com", "www.youtube.com", "m.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com", "youtu.be"
      id = if uri.host == "youtu.be"
        uri.path.delete_prefix("/")
      elsif uri.path == "/watch"
        URI.decode_www_form(uri.query.to_s).to_h["v"]
      else
        uri.path.match(%r{\A/(?:embed|shorts|live)/([^/]+)\z})&.captures&.first
      end
      "https://www.youtube-nocookie.com/embed/#{id}?autoplay=1&playsinline=1" if id&.match?(/\A[\w-]{11}\z/)
    when "vimeo.com", "www.vimeo.com", "player.vimeo.com"
      id = uri.path.match(%r{\A/(?:video/)?(\d+)\z})&.captures&.first
      "https://player.vimeo.com/video/#{id}?autoplay=1" if id
    end
  rescue URI::InvalidURIError, ArgumentError
    nil
  end

  def video_file?
    availability != "removed" && URI.parse(url).path.match?(/\.(mp4|webm|ogv)\z/i)
  rescue URI::InvalidURIError
    false
  end
end

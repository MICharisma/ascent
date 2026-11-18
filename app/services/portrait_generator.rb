require "base64"
require "net/http"
require "stringio"

class PortraitGenerator
  class Disabled < StandardError; end
  class Error < StandardError; end

  STYLES = {
    "pen_ink" => { label: "Pen and ink portrait", scene: "A pen-and-ink portrait with expressive cross-hatching on warm white paper." },
    "legislative_chamber" => { label: "Legislative chamber", scene: "An illustrative action scene of the subject speaking in a legislative chamber." },
    "voting_booth" => { label: "Voting booth", scene: "An illustrative scene of the subject standing at a voting booth. Keep the ballot private and show no voting choice." },
    "american_pastime" => { label: "American pastime", scene: "An illustrative everyday American pastime scene." }
  }.freeze
  PASTIMES = [ "driving along a country road", "volunteering at a community food pantry", "enjoying a picnic in a public park",
    "watching a local baseball game", "tending a community garden", "preparing food at a neighborhood cookout" ].freeze

  def self.enabled?
    Rails.application.config.x.portrait_generation.enabled == true
  end

  def initialize(subject:, reference_image:, style:, random: Random.new)
    @subject, @reference_image, @style, @random = subject, reference_image, style.to_s, random
  end

  def call
    raise Disabled, "Portrait generation is disabled pending legal review" unless self.class.enabled?
    raise ArgumentError, "Subject must be a citizen or candidacy" unless @subject.is_a?(Citizen) || @subject.is_a?(Candidacy)
    citizen = @subject.is_a?(Candidacy) ? @subject.citizen : @subject
    unless @reference_image.file.attached? && @reference_image.image_placements.exists?(subject: [ citizen, @subject ])
      raise ArgumentError, "Choose an uploaded reference image from this profile"
    end
    style = STYLES.fetch(@style) { raise ArgumentError, "Unknown portrait style" }
    pastime = PASTIMES.sample(random: @random) if @style == "american_pastime"
    prompt = "Create an AI-generated illustration of #{citizen.full_name} using the attached image as the identity reference. " \
      "Preserve their facial features. #{style.fetch(:scene)} #{"Show the subject #{pastime}." if pastime} " \
      "This is an imagined illustration, not evidence that an event occurred. Do not add claims, slogans, party symbols, or endorsements."
    model = Rails.application.config.x.portrait_generation.model
    bytes = request_image(prompt, model)
    metadata = { ai_generated: true, portrait_generation: { style: @style, pastime: pastime, prompt: prompt, model: model,
      generated_at: Time.current.iso8601, reference_image_id: @reference_image.id, reference_blob_id: @reference_image.file.blob.id } }
    Image.transaction do
      image = Image.new(alt_text: "AI-generated #{style.fetch(:label).downcase} of #{citizen.display_name}", credit: "AI-generated with OpenAI")
      image.file.attach(io: StringIO.new(bytes), filename: "#{citizen.full_name.parameterize}-#{@style}.png", content_type: "image/png", metadata: metadata)
      image.save!
      @subject.image_placements.create!(image: image, position: (@subject.image_placements.maximum(:position) || -1) + 1)
      image
    end
  end

  private

  def request_image(prompt, model)
    api_key = ENV["OPENAI_API_KEY"].presence || raise(Error, "OPENAI_API_KEY is not configured")
    uri = URI("https://api.openai.com/v1/images/edits")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{api_key}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(model: model, prompt: prompt, n: 1, size: "1024x1536", quality: "medium", output_format: "png",
      images: [ { image_url: "data:#{@reference_image.file.content_type};base64,#{Base64.strict_encode64(@reference_image.file.download)}" } ])
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 180) { it.request(request) }
    raise Error, "OpenAI image edit failed with HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    Base64.strict_decode64(JSON.parse(response.body).fetch("data").fetch(0).fetch("b64_json"))
  rescue JSON::ParserError, KeyError, IndexError, TypeError, ArgumentError
    raise Error, "OpenAI returned an invalid image response"
  end
end

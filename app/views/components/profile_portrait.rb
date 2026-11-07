# frozen_string_literal: true

class Views::Components::ProfilePortrait < Views::ApplicationView
  prop :citizen, Citizen
  prop :image, _Nilable(::Image), default: nil
  prop :variant, Symbol, default: :portrait

  include Phlex::Rails::Helpers::URLFor

  def view_template
    figure(class: "profile-portrait") do
      if @image
        source = @image.file.attached? ? url_for(@image.file.variant(@variant)) : @image.url
        img(src: source, alt: @image.alt_text.presence || "Photo of #{@citizen.full_name}", class: "profile-portrait-image",
          width: 400, height: 500, decoding: "async", referrerpolicy: "no-referrer")
        span(class: "row-badge row-badge-mock") { "AI-generated illustration" } if @image.ai_generated?
        if @image.credit.present? || @image.source_url.present?
          figcaption(class: "profile-portrait-credit") do
            if @image.source_url.present?
              a(href: @image.source_url, target: "_blank", rel: "noopener noreferrer") { @image.credit.presence || "Photo source" }
            else
              plain @image.credit
            end
          end
        end
      else
        div(class: "profile-portrait-placeholder", role: "img", aria: { label: "No portrait for #{@citizen.full_name}" }) do
          [ @citizen.first_name, @citizen.last_name ].compact_blank.map { it.first }.join
        end
      end
    end
  end
end

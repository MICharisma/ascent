class Views::Components::ProfileImages < Views::ApplicationView
  prop :citizen, Citizen
  prop :images, Array

  include Phlex::Rails::Helpers::URLFor

  def view_template
    return if @images.size < 2

    section(class: "place-section", id: "profile-images") do
      section_heading("Photos", pluralize(@images.size, "image"))
      div(class: "profile-image-gallery") do
        @images.drop(1).each do |image|
          div do
            ProfilePortrait(citizen: @citizen, image: image, variant: :thumbnail)
            a(href: image.file.attached? ? url_for(image.file.variant(:large)) : image.url,
              class: "text-link", target: "_blank", rel: "noopener noreferrer") { "Open image" }
          end
        end
      end
    end
  end
end

class Views::Components::ProfileImageFields < Views::ApplicationView
  prop :record, _Any

  def view_template
    section(class: "place-section") do
      h2 { "Images" }
      p(class: "card-text") { "Images can be shared with other citizens and candidacies. Editing image details updates them wherever that image is used. Lower display orders appear first." }
      placements = @record.image_placements.to_a
      placements.each_with_index { |placement, index| placement_fields(placement, index) }
      placement_fields(ImagePlacement.new, placements.size, existing: true)
      placement_fields(ImagePlacement.new, placements.size + 1)
      fieldset(class: "profile-image-fields", disabled: true) do
        legend { "AI portraits" }
        p(class: "card-text") { "Portrait generation is disabled pending legal review." }
        label(for: "portrait-style") { "Style" }
        select(id: "portrait-style", class: "text-input") do
          PortraitGenerator::STYLES.each { |value, style| option(value: value) { style.fetch(:label) } }
        end
        button(type: "button", class: "pill-button pill-button-outline", disabled: true) { "Generate portrait" }
      end
    end
  end

  private

  def placement_fields(placement, index, existing: false)
    prefix = "#{@record.model_name.param_key}[image_placements_attributes][#{index}]"
    fieldset(class: "profile-image-fields") do
      legend { placement.persisted? ? "Image #{index + 1}" : (existing ? "Use an existing image" : "Add a new image") }
      input(type: "hidden", name: "#{prefix}[id]", value: placement.id) if placement.persisted?
      if existing
        id = "existing-image-#{index}"
        label(for: id) { "Image" }
        select(id: id, name: "#{prefix}[image_id]", class: "text-input") do
          option(value: "") { "Choose an image" }
          ::Image.order(:id).each { |image| option(value: image.id) { image.name } }
        end
      else
        image = placement.image || ::Image.new
        image_prefix = "#{prefix}[image_attributes]"
        if image.persisted?
          input(type: "hidden", name: "#{prefix}[image_id]", value: image.id)
          input(type: "hidden", name: "#{image_prefix}[id]", value: image.id)
        end
        image_input(image_prefix, :file, "Upload image", nil, type: "file", accept: ::Image::CONTENT_TYPES.join(","))
        image_input(image_prefix, :url, "Original image URL", image.url, type: "url")
        image_input(image_prefix, :alt_text, "Image description", image.alt_text)
        image_input(image_prefix, :credit, "Photo credit", image.credit)
        image_input(image_prefix, :source_url, "Photo source URL", image.source_url, type: "url")
      end
      image_input(prefix, :position, "Display order", placement.position, type: "number", min: 0, step: 1)
      if placement.persisted?
        label do
          input(type: "checkbox", name: "#{prefix}[_destroy]", value: "1")
          plain "Remove from this profile"
        end
      end
    end
  end

  def image_input(prefix, attribute, text, value, **attributes)
    id = "#{prefix}[#{attribute}]".gsub(/[^a-zA-Z0-9]/, "_")
    label(for: id) { text }
    input(id: id, name: "#{prefix}[#{attribute}]", value: value, class: "text-input", type: "text", **attributes)
  end
end

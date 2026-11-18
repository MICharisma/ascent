require "rails_helper"

RSpec.describe "Shared profile images" do
  it "allows many images per citizen and reuses an image across citizens and candidacies" do
    citizen = create(:citizen)
    other = create(:citizen)
    candidacy = create(:candidacy, citizen: citizen)
    shared = create(:image)
    second = create(:image)
    citizen.image_placements.create!(image: shared, position: 10)
    citizen.image_placements.create!(image: second, position: 0)
    other.images << shared
    candidacy.images << shared

    expect(citizen.images).to eq([ second, shared ])
    expect(shared.citizens).to contain_exactly(citizen, other)
    expect(shared.candidacies).to eq([ candidacy ])
    expect(build(:image_placement, image: shared, subject: citizen)).not_to be_valid
    expect(build(:image_placement, image: shared, subject: create(:organization))).not_to be_valid
    expect(build(:image_placement, position: -1)).not_to be_valid
    expect(build(:image, url: "javascript:alert(1)")).not_to be_valid
  end

  it "removes a placement without deleting the shared image or other placements" do
    image = create(:image)
    first = create(:image_placement, image: image)
    second = create(:image_placement, image: image)

    expect(image.destroy).to be(false)
    expect { first.subject.destroy! }.not_to change(Image, :count)
    expect(second.reload.image).to eq(image)
    expect(image.reload.image_placements).to eq([ second ])
  end

  it "ignores blank image form rows while saving new and reused images" do
    citizen = create(:citizen)
    shared = create(:image)
    citizen.update!(image_placements_attributes: [
      { image_id: shared.id, position: 2 },
      { position: 1, image_attributes: { url: "https://images.example.org/portrait.jpg", credit: "City Studio" } },
      { image_id: "", position: "0" },
      { position: "0", image_attributes: { url: "", alt_text: "", credit: "", source_url: "" } }
    ])

    expect(citizen.images.count).to eq(2)
    expect(citizen.images.first.credit).to eq("City Studio")
    expect(citizen.images.last).to eq(shared)
  end

  it "stores uploads and produces the named thumbnail sizes" do
    image = create(:image, :uploaded)
    dimensions = { avatar: [ 96, 96 ], thumbnail: [ 256, 320 ], portrait: [ 800, 1000 ], large: [ 640, 800 ] }
    dimensions.each do |name, expected|
      variant = image.file.variant(name).processed
      pixels = Vips::Image.new_from_buffer(variant.download, "")
      expect([ pixels.width, pixels.height ]).to eq(expected)
    end
    expect(image.url).to be_nil
    expect(image.file.blob.service_name).to eq("test")
    expect(build(:image, url: nil)).not_to be_valid
  end

  it "rejects unsupported or oversized attachments" do
    image = build(:image, :uploaded)
    image.file.blob.content_type = "text/html"
    expect(image).not_to be_valid
    image.file.blob.content_type = "image/png"
    image.file.blob.byte_size = Image::MAX_FILE_SIZE + 1
    expect(image).not_to be_valid
  end
end

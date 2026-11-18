require "rails_helper"

RSpec.describe "Citizen routes", type: :routing do
  it "uses the Citizen controller for directory and profile pages" do
    expect(get: "/citizens").to route_to("citizens#index")
    expect(get: "/citizens/12").to route_to("citizens#show", id: "12")
    expect(get: "/people/12").not_to be_routable
  end

  it "keeps voter accounts on their own controller" do
    expect(get: "/voters/12").to route_to("voters#show", id: "12")
  end
end

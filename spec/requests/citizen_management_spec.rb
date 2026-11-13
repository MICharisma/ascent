require "rails_helper"

RSpec.describe "Citizen management", type: :request do
  let(:attributes) { { first_name: "Marisol", last_name: "Vega", email: "marisol.vega@example.com" } }

  it "requires sign-in for writes while keeping the directory public" do
    get citizens_path
    expect(response).to have_http_status(:ok)

    expect { post citizens_path, params: { citizen: attributes } }.not_to change(Citizen, :count)
    expect(response).to redirect_to(new_voter_session_path)
  end

  it "redirects a consolidated Citizen's old page to the survivor" do
    survivor = create(:citizen)
    CitizenMerge.create!(old_citizen_id: 987654321, citizen: survivor, rizz_entity_id: SecureRandom.uuid, performed_by: "maintainer", snapshot: {})
    get citizen_path(987654321)
    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to(citizen_path(survivor))
  end

  it "prevents a regular voter from creating a citizen" do
    sign_in create(:voter)

    expect { post citizens_path, params: { citizen: attributes } }.not_to change(Citizen, :count)
    expect(response).to redirect_to(root_path)
  end

  it "lets an admin create, update, and delete through Citizen form parameters" do
    sign_in create(:admin_voter)

    expect { post citizens_path, params: { citizen: attributes } }.to change(Citizen, :count).by(1)
    citizen = Citizen.find_by!(email: attributes[:email])
    expect(response).to redirect_to(citizen_path(citizen))

    patch citizen_path(citizen), params: { citizen: { last_name: "Delgado" } }
    expect(citizen.reload.last_name).to eq("Delgado")
    expect(response).to redirect_to(citizen_path(citizen))

    expect { delete citizen_path(citizen) }.to change(Citizen, :count).by(-1)
    expect(response).to redirect_to(citizens_path)
  end
end

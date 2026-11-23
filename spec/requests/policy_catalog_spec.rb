require "rails_helper"

# Topics, issues, approaches and stances share ApplicationRecordPolicy: anyone
# lists and reads them, and only administrators add, change or remove them.
RSpec.describe "Policy catalog", type: :request do
  RESOURCES = {
    topic: ->(_) { { title: "Public Safety", description: "Community safety and emergency response." } },
    issue: ->(_) { { title: "High Crime Rates", description: "Rising downtown crime.", topic_id: create(:topic).id } },
    approach: ->(_) { { title: "Community Policing", description: "Neighborhood partnerships.", issue_id: create(:issue).id } },
    stance: ->(_) { { candidacy_id: create(:candidacy).id, approach_id: create(:approach).id, explanation: "Fund it fully.", priority_level: "high" } }
  }.freeze

  RESOURCES.each do |name, attributes|
    describe name.to_s.pluralize do
      let(:model) { name.to_s.classify.constantize }
      let(:record) { create(name) }
      let(:changed) { name == :stance ? { explanation: "Phase it in over two years." } : { title: "Revised title" } }

      def collection_path = public_send("#{model.model_name.route_key}_path")
      def member_path(record) = public_send("#{model.model_name.singular_route_key}_path", record)

      it "lists and shows #{name.to_s.pluralize} to anyone" do
        get collection_path
        expect(response).to have_http_status(:ok)
        get member_path(record)
        expect(response).to have_http_status(:ok)
      end

      it "sends a signed-out visitor to sign in before adding one" do
        expect { post collection_path, params: { name => instance_exec(nil, &attributes) } }.not_to change(model, :count)
        expect(response).to redirect_to(new_voter_session_path)
      end

      it "refuses a signed-in voter who isn't an administrator" do
        sign_in create(:voter)
        expect { post collection_path, params: { name => instance_exec(nil, &attributes) } }.not_to change(model, :count)
        patch member_path(record), params: { name => changed }
        delete member_path(record)
        expect(response).to redirect_to(root_path)
        expect(model.exists?(record.id)).to be(true)
      end

      context "as an administrator" do
        before { sign_in create(:admin_voter) }

        it "adds one" do
          expect { post collection_path, params: { name => instance_exec(nil, &attributes) } }.to change(model, :count).by(1)
          expect(response).to redirect_to(member_path(model.last))
        end

        it "changes one" do
          patch member_path(record), params: { name => changed }
          expect(response).to redirect_to(member_path(record))
          expect(record.reload).to have_attributes(changed)
        end

        it "removes one" do
          record
          expect { delete member_path(record) }.to change(model, :count).by(-1)
        end
      end
    end
  end

  it "refuses a second stance on the same approach from one candidacy" do
    sign_in create(:admin_voter)
    stance = create(:stance)
    expect do
      post stances_path, params: { stance: { candidacy_id: stance.candidacy_id, approach_id: stance.approach_id, explanation: "Again.", priority_level: "low" } }
    end.not_to change(Stance, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

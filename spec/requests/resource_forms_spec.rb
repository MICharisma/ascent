require 'rails_helper'

# Every resource's new and edit pages render its Superform form inside the ResourceFormPage shell.
RSpec.describe "Resource forms", type: :request do
  let(:admin) { create(:admin_voter, first_name: "Rosa", last_name: "Delgado", email: "rosa.delgado@example.com") }

  before { sign_in admin }

  FORMED_RESOURCES = %i[
    approach area_of_concern candidacy county country district election governance_type governing_body
    issue municipality office official_code citizen policy position race rating residence stance state
    topic voter_race_baseline voter year
  ].freeze

  FORMED_RESOURCES.each do |resource|
    it "renders the new and edit #{resource.to_s.humanize.downcase} forms" do
      record = create(resource)
      human = record.model_name.human

      get polymorphic_path(record.class, action: :new)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(<form action="#{polymorphic_path(record.class)}" method="post"))
      expect(response.body).to include(%(value="Create #{human}"))

      get polymorphic_path(record, action: :edit)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(<form action="#{polymorphic_path(record)}" method="post"))
      expect(response.body).to include('<input name="_method" type="hidden" value="patch">', %(value="Update #{human}"))
      expect(response.body).to include(%(<h1>Editing #{human.downcase}</h1>))
    end
  end

  it "labels each field, prefills it, and marks the invalid ones after a failed save" do
    issue = create(:affordable_housing_issue)

    get edit_issue_path(issue)
    expect(response.body).to include('<label for="issue_title">Title</label>')
    expect(response.body).to include('<label for="issue_topic_id">Topic</label>')
    expect(response.body).to include(%(<input id="issue_title" name="issue[title]" type="text" value="Affordable Housing Shortage">))
    expect(response.body).to include(%(<option selected value="#{issue.topic_id}">))

    post issues_path, params: { issue: { title: "", description: "", topic_id: "" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('class="form-errors"')
    expect(response.body).to include('<option value="" selected>Select a topic</option>')
    expect(response.body).to include('<select id="issue_topic_id" name="issue[topic_id]" class="error">')
  end

  it "saves through the converted form's field names" do
    topic = create(:housing_topic)

    post issues_path, params: { issue: { title: "Eviction Filings Rising", description: "More families face eviction.", topic_id: topic.id } }

    expect(Issue.find_by(title: "Eviction Filings Rising").topic).to eq(topic)
  end
end

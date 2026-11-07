class Views::Candidacies::CandidacyForm < Views::Components::Forms::Base
  def view_template
    row field(:citizen_id).collection_select(::Citizen.all, text: :name, prompt: "Select a citizen"), label: "Citizen"
    row field(:race_id).collection_select(::Race.with_naming_details, text: :name, prompt: "Select a race"), label: "Race"
    row field(:status).text
    row field(:announcement_date).date
    row field(:participation).select_choices([ [ "Active", "active" ], [ "Inactive", "inactive" ], [ "Off-ballot, approvable", "off_ballot" ] ])
    row field(:platform_summary).textarea(rows: 4)
    ProfileImageFields(record: model)
  end
end

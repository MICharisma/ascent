class Views::Citizens::NewView < Views::ApplicationView
  prop :citizen, Citizen

  def view_template
    ResourceFormPage(record: @citizen) { render Views::Citizens::CitizenForm.new(@citizen, enctype: "multipart/form-data") }
  end
end

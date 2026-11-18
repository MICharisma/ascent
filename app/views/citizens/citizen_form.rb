class Views::Citizens::CitizenForm < Views::Components::Forms::Base
  def view_template
    row field(:first_name).text
    row field(:last_name).text
    row field(:middle_name).text
    row field(:email).text
    row field(:birth_date).date
    row field(:bio).textarea(rows: 4)
    ProfileImageFields(record: model)
  end
end

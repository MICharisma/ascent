# A name Jev couldn't read with confidence goes to Rizz's reviewers (rake
# rizz:review_names). Their decision comes back as the reading's outcome:
# settled with the reading they chose, or rejected when none fit, and
# reviewed_by records who decided.
class AddReviewsToCitizenNameReadings < ActiveRecord::Migration[8.1]
  def change
    add_column :citizen_name_readings, :reviewed_by, :string
    remove_check_constraint :citizen_name_readings, "outcome IN ('jev', 'overflow')", name: "citizen_name_readings_outcome"
    add_check_constraint :citizen_name_readings, "outcome IN ('jev', 'overflow', 'settled', 'rejected')", name: "citizen_name_readings_outcome"
    remove_check_constraint :citizen_name_readings, "outcome <> 'jev' OR parts IS NOT NULL", name: "citizen_name_readings_parts"
    add_check_constraint :citizen_name_readings, "outcome NOT IN ('jev', 'settled') OR parts IS NOT NULL", name: "citizen_name_readings_parts"
  end
end

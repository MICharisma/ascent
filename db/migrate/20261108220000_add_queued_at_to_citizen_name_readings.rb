# When rake rizz:review_names last queued the reading in Rizz's review
# queue, so a name Jev later reads with confidence can be withdrawn there.
class AddQueuedAtToCitizenNameReadings < ActiveRecord::Migration[8.1]
  def change
    add_column :citizen_name_readings, :queued_at, :datetime
  end
end

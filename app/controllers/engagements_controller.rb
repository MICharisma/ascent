class EngagementsController < ApplicationController
  def index
    engagements = current_voter.engagements.includes(:engageable).recent_first
    render Views::Engagements::IndexView.new(engagements: engagements)
  end

  def create
    engageable = find_engageable
    return head :not_found unless engageable
    return head :unprocessable_content unless Engagement.kinds.key?(params[:kind])

    current_voter.engagements.find_or_create_by!(engageable: engageable, kind: params[:kind])
    respond_with_action_bar engageable
  end

  def destroy
    engagement = current_voter.engagements.find(params.expect(:id))
    engagement.destroy!
    respond_with_action_bar engagement.engageable
  end

  private

  def find_engageable
    Engagement.engageable_class(params[:engageable_type].to_s)&.find_by(id: params[:engageable_id])
  end

  def respond_with_action_bar(engageable)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(engageable, :action_bar), Views::Components::ActionBar.new(record: engageable))
      end
      format.html { redirect_back_or_to engageable }
    end
  end
end

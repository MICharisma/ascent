class ApplicationController < ActionController::Base
  include AnalyticsTracking
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern, unless: -> { controller_name.in?(%w[public_mountains errors]) }

  include Pagy::Method

  # Include ActionPolicy authorization
  include ActionPolicy::Controller
  authorize :voter, through: :current_voter
  append_before_action :authorize_action_policy_resource!
  # An action that authorizes nothing raises, so a new controller cannot skip its policy by accident.
  verify_authorized unless: :devise_controller?

  # Make current_voter available as a helper method in views
  helper_method :current_voter
  helper_method :current_user

  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def inviting_voter
    @inviting_voter ||= Voter.find_by(id: session["devise.inviter_id"])
  end

  def pagy(paginator = :offset, collection, **options)
    super
  rescue Pagy::RangeError => error
    super(paginator, collection, **options, page: error.pagy.last)
  end

  rescue_from ActionPolicy::Unauthorized, with: :handle_unauthorized!

  def default_authorization_policy_class
    ApplicationRecordPolicy
  end

  def configure_permitted_parameters
    # For sign up
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :first_name, :last_name ])

    # Optional: for account update
    devise_parameter_sanitizer.permit(:account_update, keys: [ :first_name, :last_name ])
  end

  def current_user
    current_voter
  end

  def authorize_action_policy_resource!
    return if devise_controller?

    target = action_policy_target
    return unless target

    authorize! target, to: action_policy_rule
  end

  def action_policy_target
    klass = controller_name.classify.safe_constantize
    # Plain models such as Mountain have no records to find; their controllers authorize themselves.
    return unless klass && klass < ActiveRecord::Base

    case action_name
    when "index", "new", "create"
      klass
    else
      params[:id] ? klass.find(params[:id]) : klass
    end
  end

  def action_policy_rule
    "#{action_name}?".to_sym
  end

  def handle_unauthorized!(_exception)
    destination = current_voter ? root_path : new_voter_session_path
    message = current_voter ? "You are not authorized to perform that action." : "Please sign in to continue."

    redirect_to destination, alert: message
  end
end

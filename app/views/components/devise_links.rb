class Views::Components::DeviseLinks < Views::ApplicationView
  def initialize
  end

  def view_template
    div(class: "devise-links") do
      if current_voter
        authenticated_links
      else
        unauthenticated_links
      end
    end
  end

  private

  def authenticated_links
    span(class: "voter-greeting") { "Hello, #{current_voter.first_name}" }
    link_to "Saved", engagements_path, class: "nav-auth-link saved-link"
    link_to "Profile", edit_voter_path(current_voter), class: "nav-auth-link"
    link_to "Sign Out", destroy_voter_session_path,
            class: "nav-auth-link",
            data: { turbo_method: :delete }
  end

  def unauthenticated_links
    link_to "Sign In", new_voter_session_path, class: "nav-auth-link sign-in-link"
    if Voter.google_sign_in_available?
      google_sign_in_button
    else
      link_to "Sign Up", new_voter_registration_path, class: "nav-auth-link sign-up-link"
    end
  end

  def google_sign_in_button
    origin = request.fullpath if respond_to?(:request, true) && request&.get?
    button_to voter_google_oauth2_omniauth_authorize_path(origin: origin), method: :post,
      class: "google-sign-in",
      aria: { label: "Get In with Google to Ascent" },
      form: { class: "google-sign-in-form", data: { turbo: false, turbo_frame: "_top" } } do
      img(src: "/google-g.png", width: 18, height: 18, alt: "")
      span(class: "google-sign-in-label") { "Get In" }
      img(src: "/icon.svg", width: 20, height: 20, alt: "", class: "google-sign-in-site")
    end
  end
end

Rails.application.routes.draw do
  resource :map, only: :show, controller: "maps" do
    get :features
  end
  get "boundary_outlines/:place_type/:place_id(.:format)", to: "boundary_outlines#show",
    as: :boundary_outline, constraints: { format: /svg|png/ }, defaults: { format: "svg" }

  get "glossary" => "pages#glossary", as: :glossary
  get "faq" => "pages#faq", as: :faq
  get "supporters" => "pages#supporters", as: :supporters
  get "approval-voting" => "pages#approval_voting", as: :approval_voting
  get "terms-of-service" => "pages#terms_of_service", as: :terms_of_service
  get "inquiries" => "inquiries#new", as: :new_inquiry
  post "inquiries" => "inquiries#create", as: :inquiries

  resources :engagements, only: [ :index, :create, :destroy ], path: "saved"
  resources :official_codes
  resources :policies do
    resources :official_codes, only: [ :index ]
  end
  resources :stances
  resources :approaches
  resources :issues do
    resources :approaches, only: [ :index ]
  end
  resources :topics do
    resources :issues, only: [ :index ]
  end
  resources :governing_bodies do
    resources :policies, only: [ :index ]
  end
  resources :area_of_concerns
  resources :governance_types do
    resources :governing_bodies, only: [ :index ]
  end
  resources :voter_race_baselines
  resources :ratings

  get "invite/:token", to: "invites#show", as: :invite
  resources :invites, only: %i[index create]
  get "influencers/:token", to: "influencers#show", as: :influencer
  resource :influencer_profile, only: :show, path: "profile/influencer"
  resources :voter_links, only: %i[create update] do
    patch :move, on: :member
  end
  resources :voter_statements, only: %i[create update] do
    patch :move, on: :member
  end
  devise_for :voters, controllers: { registrations: "voters/registrations", omniauth_callbacks: "voters/omniauth_callbacks" }
  resources :voters do
    patch :hide_profile, on: :member
  end
  resources :channels, only: %i[index update]
  resources :residences
  resources :candidacies
  resources :citizens
  resources :organizations, only: %i[index show]
  resources :parties, only: %i[index show]
  resources :endorsements, only: %i[index show]
  resource :ballot, only: :show
  resource :residence_claim, only: %i[new create], path: "ballot/residence" do
    post :preview
  end
  resources :past_residences, only: %i[index new create destroy], path: "ballot/residences" do
    patch :move_out, on: :member
  end
  resources :mock_elections, only: [ :new, :create, :destroy ]
  get "races/:race_id/results", to: "race_results#show", as: :race_results
  get "candidacies/:id/card", to: "candidacy_cards#show", as: :candidacy_card
  resources :elections do
    resources :races, only: [ :index ]
  end
  resources :races
  resources :years
  resources :offices do
    resources :races, only: [ :index ]
  end
  resources :positions
  resources :municipalities
  resources :counties
  resources :districts
  resources :states do
    resources :municipalities, only: [ :index ]
  end
  resources :countries do
    resources :states, only: [ :index ]
  end

  resources :mountains, only: [ :index, :show, :edit, :update ] do
    member do
      post :simulate
      patch :primary_candidates
      patch :draft
      delete :draft, action: :discard
      post :save
      post :share
      delete :share, action: :unshare
    end
  end
  resources :public_mountains, only: :show
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Development only: serve SimpleCov coverage reports
  if Rails.env.development?
    mount Rack::Files.new(Rails.root.join("coverage")), at: "/coverage"
    mount Rack::Files.new(Rails.root.join("app/assets/builds")), at: "/dev-assets"
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "pages#home"
end

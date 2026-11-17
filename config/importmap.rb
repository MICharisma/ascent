# Pin npm packages by running ./bin/importmap

pin "application"
pin "ahoy", to: "ahoy.js"
pin "analytics", to: "analytics.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "loglevel", to: "loglevel.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "shared-ratings/dimension", to: "shared_ratings/dimension.js"
pin "shared-ratings/horizontal-drag", to: "shared_ratings/horizontal_drag.js"
pin "shared-ratings/suggestions-controller", to: "shared_ratings/suggestions_controller.js"
pin "echarts", preload: false # @6.1.0, the single-file ESM build from dist/echarts.esm.min.js
pin "gsap" # @3.15.0, jsDelivr's +esm bundle
pin "chart_theme", to: "chart_theme.js"
pin "leaflet", preload: false

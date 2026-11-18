module ApplicationHelper
  include ScaffoldUiHelper

  def load_google_fonts
    font_header +
    tag.link(rel: "stylesheet", href: font_url)
  end

  def font_header
    tag.link(rel: "preconnect", href: "https://fonts.googleapis.com") +
    tag.link(rel: "preconnect", href: "https://fonts.gstatic.com", crossorigin: true)
  end

  def font_url
    "https://fonts.googleapis.com/css2?family=" +
    font_list.values.join("&family=") + "&display=swap"
  end

  def font_list
    {
      "Bricolage Grotesque" => "Bricolage+Grotesque:opsz,wdth,wght@12..96,75..100,200..800",
      "Google Sans" => "Google+Sans:wght@500;600",
      "Martian Mono" => "Martian+Mono:wdth,wght@75..112.5,300..700"
    }
  end

  def umami_tracker
    return unless ENV["UMAMI_SCRIPT_URL"].present? && ENV["UMAMI_WEBSITE_ID"].present?

    tag.script defer: true, src: ENV["UMAMI_SCRIPT_URL"], data: {
      website_id: ENV["UMAMI_WEBSITE_ID"], domains: ENV["UMAMI_DOMAINS"], exclude_search: true, exclude_hash: true
    }
  end
end

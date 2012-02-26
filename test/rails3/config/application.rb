require "action_controller/railtie"
module MyApp
  class Application < Rails::Application
    config.session_store :cookie_store, :key=>"_my_app_session"
    config.secret_token = "Stay hungry. Stay foolish. -- Steve Jobs"
    config.active_support.deprecation = :stderr 

    config.after_initialize do
      config.oauth.database = DATABASE
      config.oauth.host = "example.org"
      config.oauth.collection_prefix = "oauth2_prefix"
      config.oauth.authenticator = lambda do |username, password|
        "Batman" if username == "cowbell" && password == "more"
      end
      config.middleware.use Rack::OAuth2::Server::Admin.mount
    end
  end
end
Rails.application.config.root = File.dirname(__FILE__) + "/.."
require Rails.root + "config/routes"

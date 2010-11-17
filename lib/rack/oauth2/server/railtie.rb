require "rack/oauth2/server"
require "rack/oauth2/rails"
require "rails"

module Rack
  module OAuth2
    class Server
      # Rails 3.x integration.
      class Railtie < ::Rails::Railtie # :nodoc:
        config.oauth = Server::Options.new

        initializer "rack-oauth2-server" do |app|
          app.middleware.use ::Rack::OAuth2::Server, app.config.oauth
          config.oauth.logger ||= ::Rails.logger
          class ::ActionController::Base
            helper ::Rack::OAuth2::Rails::Helpers
            include ::Rack::OAuth2::Rails::Helpers
            extend ::Rack::OAuth2::Rails::Filters
          end
        end
      end
    end
  end
end

# Rails 2.x initialization.
require "rack/oauth2/rails"

config.extend ::Rack::OAuth2::Rails::Configuration
config.oauth.logger ||= Rails.logger
config.middleware.use ::Rack::OAuth2::Server, config.oauth
class ActionController::Base
  helper ::Rack::OAuth2::Rails::Helpers
  include ::Rack::OAuth2::Rails::Helpers
  extend ::Rack::OAuth2::Rails::Filters
end

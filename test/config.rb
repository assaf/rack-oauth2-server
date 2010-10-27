ENV["RACK_ENV"] = "test"
require "bundler"
Bundler.setup

require "test/unit"
require "shoulda"
require "rack/test"
require "sinatra/base"

class Test::Unit::TestCase
  include Rack::Test::Methods

  def setup
    Rack::OAuth2::Models.db = Mongo::Connection.new["rack_test"]
    SimpleApp.end_user_sees = nil
  end

  def app
    @app ||= SimpleApp.new
  end

  def teardown
    Rack::OAuth2::Models::Client.collection.drop
    Rack::OAuth2::Models::AuthRequest.collection.drop
    Rack::OAuth2::Models::AccessGrant.collection.drop
    Rack::OAuth2::Models::AccessToken.collection.drop
  end
end

$: << File.dirname(__FILE__) + "/../lib"
require "rack/oauth2/server"
require File.dirname(__FILE__) + "/simple_app"

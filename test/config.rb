ENV["RACK_ENV"] = "test"
require "bundler"
Bundler.setup

require "test/unit"
require "rack/test"
require "shoulda"
require "ap"
require "json"
require "sinatra/base"

class Test::Unit::TestCase
  include Rack::Test::Methods

  def setup
    Rack::OAuth2::Models.db = Mongo::Connection.new["rack_test"]
    SimpleApp.end_user_sees = nil
    @app = SimpleApp.new
    @client = Rack::OAuth2::Models::Client.create(:display_name=>"UberClient", :redirect_uri=>"http://uberclient.dot/callback")
  end

  attr_reader :client, :app

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

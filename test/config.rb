ENV["RACK_ENV"] = "test"
require "bundler"
Bundler.setup

require "test/unit"
require "rack/test"
require "shoulda"
require "ap"
require "json"
require "sinatra/base"
require "rack/oauth2/sinatra"

class Test::Unit::TestCase
  include Rack::Test::Methods

  def setup
    Rack::OAuth2::Server.db = Mongo::Connection.new["rack_test"]
    SimpleApp.end_user_sees = nil
    @app = SimpleApp.new
    @client = Rack::OAuth2::Server::Client.create(:display_name=>"UberClient", :redirect_uri=>"http://uberclient.dot/callback")
  end

  attr_reader :client, :app

  def teardown
    Rack::OAuth2::Server::Client.collection.drop
    Rack::OAuth2::Server::AuthRequest.collection.drop
    Rack::OAuth2::Server::AccessGrant.collection.drop
    Rack::OAuth2::Server::AccessToken.collection.drop
  end
end

$: << File.dirname(__FILE__) + "/../lib"
require "rack/oauth2/server"
require File.dirname(__FILE__) + "/simple_app"

require "bundler"
Bundler.setup
require "test/unit"
require "rack/test"
require "shoulda"
require "ap"
require "json"
$: << File.dirname(__FILE__) + "/../lib"
require "rack/oauth2/server"


ENV["RACK_ENV"] = "test"
DATABASE = Mongo::Connection.new["rack_test"]
FRAMEWORK = ENV["FRAMEWORK"] || "sinatra"


case FRAMEWORK
when "sinatra", nil

  require "sinatra/base"
  puts "Testing with Sinatra #{Sinatra::VERSION}"
  require File.dirname(__FILE__) + "/sinatra/my_app"
  
  class Test::Unit::TestCase
    def app
      MyApp.new
    end
  end

when "rails2"

  require "initializer"
  require "action_controller"
  RAILS_ROOT = File.dirname(__FILE__) + "/rails"
  RAILS_ENV = "test"

  class << Rails
    def vendor_rails?
      false
    end
  end
  require RAILS_ROOT + "/config/environment"
  puts "Testing with Rails #{Rails.version}"
  
  class Test::Unit::TestCase
    def app
      ActionController::Dispatcher.new
    end
  end

else
  puts "Unknown framework #{FRAMEWORK}"
  exit -1
end


class Test::Unit::TestCase
  include Rack::Test::Methods

  def setup
    Rack::OAuth2::Server.database = DATABASE
    @client = Rack::OAuth2::Server::Client.create(:display_name=>"UberClient", :redirect_uri=>"http://uberclient.dot/callback")
  end

  attr_reader :client, :end_user

  def teardown
    Rack::OAuth2::Server::Client.collection.drop
    Rack::OAuth2::Server::AuthRequest.collection.drop
    Rack::OAuth2::Server::AccessGrant.collection.drop
    Rack::OAuth2::Server::AccessToken.collection.drop
  end
end

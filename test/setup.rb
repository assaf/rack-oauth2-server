require "bundler"
Bundler.setup
require "test/unit"
require "rack/test"
require "shoulda"
require "timecop"
require "ap"
require "json"
$: << File.dirname(__FILE__) + "/../lib"
$: << File.expand_path(File.dirname(__FILE__) + "/..")
require "rack/oauth2/server"
require "rack/oauth2/server/admin"


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
      Rack::Builder.new do
        map("/oauth/admin") { run Rack::OAuth2::Server::Admin }
        map("/") { run MyApp }
      end
    end

    def config
      MyApp.oauth
    end
  end

when "rails"

  RAILS_ENV = "test"
  RAILS_ROOT = File.dirname(__FILE__) + "/rails3"
  begin
    require "rails"
  rescue LoadError
  end

  if defined?(Rails::Railtie)
    # Rails 3.x
    require "rack/oauth2/server/railtie"
    require File.dirname(__FILE__) + "/rails3/config/environment"
    puts "Testing with Rails #{Rails.version}"
  
    class Test::Unit::TestCase
      def app
        Rails.application
      end

      def config
        Rails.configuration.oauth
      end
    end

  else
    # Rails 2.x
    RAILS_ROOT = File.dirname(__FILE__) + "/rails2"
    require "initializer"
    require "action_controller"
    require File.dirname(__FILE__) + "/rails2/config/environment"
    puts "Testing with Rails #{Rails.version}"
  
    class Test::Unit::TestCase
      def app
        ActionController::Dispatcher.new
      end

      def config
        Rails.configuration.oauth
      end
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

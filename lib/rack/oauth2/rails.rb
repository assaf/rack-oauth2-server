require "rack/oauth2/server"

module Rack
  module OAuth2

    # Rails support.
    #
    # Adds oauth instance method that returns Rack::OAuth2::Helper, see there for
    # more details.
    #
    # Adds oauth_required filter method. Use this filter with actions that require
    # authentication, and with actions that require client to have a specific
    # access scope.
    #
    # Adds oauth setting you can use to configure the module (e.g. setting
    # available scope, see example).
    #
    # @example config/environment.rb
    #   require "rack/oauth2/rails"
    #
    #   Rails::Initializer.run do |config|
    #     config.oauth[:scope] = %w{read write}
    #     config.oauth[:authenticator] = lambda do |username, password|
    #       User.authenticated username, password
    #     end
    #     . . .
    #   end
    #
    # @example app/controllers/my_controller.rb
    #   class MyController < ApplicationController
    #
    #     oauth_required :only=>:show
    #     oauth_required :only=>:update, :scope=>"write"
    #
    #     . . .
    #
    #   protected 
    #     def current_user
    #       @current_user ||= User.find(oauth.identity) if oauth.authenticated?
    #     end
    #   end
    #
    # @see Helpers
    # @see Filters
    # @see Configuration
    module Rails

      # Helper methods available to controller instance and views.
      module Helpers
        # Returns the OAuth helper.
        #
        # @return [Server::Helper]
        def oauth
          @oauth ||= Rack::OAuth2::Server::Helper.new(request, response)
        end

        # Filter that denies access if the request is not authenticated. If you
        # do not specify a scope, the class method oauth_required will use this
        # filter; you can set the filter in a parent class and skip it in child
        # classes that need special handling.
        def oauth_required
          head oauth.no_access! unless oauth.authenticated?
        end
      end

      # Filter methods available in controller.
      module Filters
        
        # Adds before filter to require authentication on all the listed paths.
        # Use the :scope option if client must also have access to that scope.
        #
        # @param [Hash] options Accepts before_filter options like :only and
        # :except, and the :scope option.
        def oauth_required(options = {})
          if scope = options.delete(:scope)
            before_filter options do |controller|
              if controller.oauth.authenticated?
                if !controller.oauth.scope.include?(scope)
                  controller.send :head, controller.oauth.no_scope!(scope)
                end
              else
                controller.send :head, controller.oauth.no_access!
              end
            end
          else
            before_filter :oauth_required, options
          end
        end
      end

      # Configuration methods available in config/environment.rb.
      module Configuration

        # Rack module settings.
        #
        # @return [Hash] Settings
        def oauth
          @oauth ||= Server::Options.new
        end
      end

    end

  end
end

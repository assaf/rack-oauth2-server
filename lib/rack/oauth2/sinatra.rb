require "rack/oauth2/server"

module Rack
  module OAuth2

    # Sinatra support.
    #
    # Adds oauth instance method that returns Rack::OAuth2::Helper, see there for
    # more details.
    #
    # Adds oauth_required class method. Use this filter with paths that require
    # authentication, and with paths that require client to have a specific
    # access scope.
    #
    # Adds oauth setting you can use to configure the module (e.g. setting
    # available scope, see example).
    #
    # @example
    #   require "rack/oauth2/sinatra"
    #   class MyApp < Sinatra::Base
    #     register Rack::OAuth2::Sinatra
    #     oauth[:scope] = %w{read write}
    #
    #     oauth_required "/api"
    #     oauth_required "/api/edit", :scope=>"write"
    #
    #     before { @user = User.find(oauth.identity) if oauth.authenticated? }
    #   end
    #
    # @see Helpers
    module Sinatra

      # Adds before filter to require authentication on all the listed paths.
      # Use the :scope option if client must also have access to that scope.
      #
      # @param [String, ...] path One or more paths that require authentication
      # @param [optional, Hash] options Currently only :scope is supported.
      def oauth_required(*args)
        options = args.pop if Hash === args.last
        scope = options[:scope] if options
        args.each do |path|
          before path do
            if oauth.authenticated?
              if scope && !oauth.scope.include?(scope)
                halt oauth.no_scope! scope
              end
            else
              halt oauth.no_access!
            end
          end
        end
      end

      module Helpers
        # Returns the OAuth helper.
        #
        # @return [Server::Helper]
        def oauth
          @oauth ||= Server::Helper.new(request, response)
        end
      end

      def self.registered(base)
        base.helpers Helpers
        base.set :oauth, Server::Options.new
        base.use Server, base.settings.oauth
      end

    end
  end
end

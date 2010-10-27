module Rack
  module OAuth2
    class Server

      # Include this in Rack::Request for each access to the OAuth resource,
      # scope and client.
      module RequestHelpers
        # OAuth request handle: you need to keep track of this during
        # authorization and pass it back to ResponseHelpers.
        def oauth_request
          @env["oauth.request"]
        end

        # The authorized resource. Whatever you put in here (typically user ID,
        # account ID, etc).
        def oauth_resource
          @env["oauth.resource"]
        end

        # The authorized scope. Client requested and was authorized access to
        # this scope. Scope if an array of names, e.g. ["view", "update"].
        def oauth_scope
          @env["oauth.scope"]
        end

        # The authorized client.
        def oauth_client
          @client ||= Models::Client.find(@env["oauth.client_id"]) if @env["oauth.client_id"]
        end
      end

    end
  end
end

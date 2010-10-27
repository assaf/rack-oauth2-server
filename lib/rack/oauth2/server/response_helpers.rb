module Rack
  module OAuth2
    class Server

      # Include this in Rack::Response for convenience methods you can use
      # during the authorization flow.
      module ResponseHelpers
        # Call this when end user grants authorization request. First argument
        # is oauth_request (see RequestHelpers), second argument is the
        # resource authorized.
        def oauth_grant!(request, resource)
          self["oauth.request"] = request
          self["oauth.resource"] = resource
        end

        # Call this when end user denies authorization request. Argument is
        # oauth_request (see RequestHelpers).
        def oauth_deny!(request)
          self["oauth.request"] = request
          self["oauth.resource"] = nil
        end

        # Call this to deny access to a resource. You can also indicate which
        # scope is necessary to access the resource.
        def oauth_no_access!(scope = nil)
          self["oauth.no_access"] = scope || []
        end
      end

    end
  end
end


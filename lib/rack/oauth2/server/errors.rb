module Rack
  module OAuth2
    class Server

      # Base class for all OAuth errors. These map to error codes in the spec.
      class Error < StandardError

        def initialize(code, message)
          super message
          @code = code.to_sym
        end

        # The OAuth error code.
        attr_reader :code
      end

      # Access token expired, client expected to request new one using refresh
      # token.
      class ExpiredTokenError < Error
        def initialize
          super :expired_token, "The access token has expired."
        end
      end

      # The client identifier provided is invalid, the client failed to
      # authenticate, the client did not include its credentials, provided
      # multiple client credentials, or used unsupported credentials type.
      class InvalidClientError < Error
        def initialize
          super :invalid_client, "Client ID and client secret do not match."
        end
      end
     
      # The provided access grant is invalid, expired, or revoked (e.g.  invalid
      # assertion, expired authorization token, bad end-user password credentials,
      # or mismatching authorization code and redirection URI).
      class InvalidGrantError < Error
        def initialize
          super :invalid_grant, "This access grant is no longer valid."
        end
      end

      # Invalid_request, the request is missing a required parameter, includes an
      # unsupported parameter or parameter value, repeats the same parameter, uses
      # more than one method for including an access token, or is otherwise
      # malformed.
      class InvalidRequestError < Error
        def initialize(message)
          super :invalid_request, message || "The request has the wrong parameters."
        end
      end

      # The requested scope is invalid, unknown, or malformed.
      class InvalidScopeError < Error
        def initialize
          super :invalid_scope, "The requested scope is not supported."
        end
      end

      # Access token expired, client cannot refresh and needs new authorization.
      class InvalidTokenError < Error
        def initialize
          super :invalid_token, "The access token is no longer valid."
        end
      end

      # The redirection URI provided does not match a pre-registered value.
      class RedirectUriMismatchError < Error
        def initialize
          super :redirect_uri_mismatch, "Must use the same redirect URI you registered with us."
        end
      end

      # The authenticated client is not authorized to use the access grant type provided.
      class UnauthorizedClientError < Error
        def initialize
          super :unauthorized_client, "You are not allowed to access this resource."
        end
      end

      # This access grant type is not supported by this server.
      class UnsupportedGrantType < Error
        def initialize
          super :unsupported_grant_type, "This access grant type is not supported by this server."
        end
      end

      # The requested response type is not supported by the authorization server.
      class UnsupportedResponseTypeError < Error
        def initialize
          super :unsupported_response_type, "The requested response type is not supported."
        end
      end

    end
  end
end

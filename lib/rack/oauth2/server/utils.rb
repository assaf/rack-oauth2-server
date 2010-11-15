module Rack
  module OAuth2
    class Server

      module Utils
        module_function

        # Parses the redirect URL, normalizes it and returns a URI object.
        #
        # Raises InvalidRequestError if not an absolute HTTP/S URL.
        def parse_redirect_uri(redirect_uri)
          uri = URI.parse(redirect_uri).normalize
          raise InvalidRequestError, "Redirect URL must be absolute URL" unless uri.absolute? && uri.host
          raise InvalidRequestError, "Redirect URL must point to HTTP/S location" unless uri.scheme == "http" || uri.scheme == "https"
          uri
        rescue
          raise InvalidRequestError, "Redirect URL looks fishy to me"
        end

        # Gives list of scopes, as either array of string, return array of
        # scope names (unique and sorted).
        def normalize_scopes(scopes)
          (Array === scopes ? scopes.join(" ") : scopes || "").split(/\s+/).compact.uniq.sort
        end

      end

    end
  end
end

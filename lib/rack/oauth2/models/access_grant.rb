module Rack
  module OAuth2
    class Server

      # The access grant is a nonce, new grant created each time we need it and
      # good for redeeming one access token.
      class AccessGrant
        class << self
          # Find AccessGrant from authentication code.
          def from_code(code)
            Server.new_instance self, collection.find_one({ :_id=>code, :revoked=>nil })
          end

          # Create a new access grant.
          def create(resource, scope, client_id, redirect_uri)
            fields = { :_id=>Server.secure_random, :resource=>resource, :scope=>scope, :client_id=>client_id, :redirect_uri=>redirect_uri,
                       :created_at=>Time.now.utc, :granted_at=>nil, :access_token=>nil, :revoked=>nil }
            collection.insert fields
            Server.new_instance self, fields
          end

          def collection
            Server.database["oauth2.access_grants"]
          end
        end

        # Authorization code. We are nothing without it.
        attr_reader :_id
        alias :code :_id
        # The resource we authorized access to.
        attr_reader :resource
        # Client that was granted this access token.
        attr_reader :client_id
        # Redirect URI for this grant.
        attr_reader :redirect_uri
        # The scope granted in this token.
        attr_reader :scope
        # Does what it says on the label.
        attr_reader :created_at
        # Tells us when (and if) access token was created.
        attr_accessor :granted_at
        # Access token created from this grant. Set and spent.
        attr_accessor :access_token
        # Timestamp if revoked.
        attr_accessor :revoked

        # Authorize access and return new access token.
        #
        # Access grant can only be redeemed once, but client can make multiple
        # requests to obtain it, so we need to make sure only first request is
        # successful in returning access token, futher requests raise
        # InvalidGrantError.
        def authorize!
          raise InvalidGrantError if self.access_token || self.revoked
          access_token = AccessToken.get_token_for(resource, scope, client_id)
          self.access_token = access_token.token
          self.granted_at = Time.now.utc
          self.class.collection.update({ :_id=>code, :access_token=>nil, :revoked=>nil }, { :$set=>{ :granted_at=>granted_at, :access_token=>access_token.token } }, :safe=>true)
          reload = self.class.collection.find_one({ :_id=>code, :revoked=>nil }, { :fields=>%w{access_token} })
          raise InvalidGrantError unless reload && reload["access_token"] == access_token.token
          return access_token
        end

        def revoke!
          self.class.collection.update({ :_id=>code, :revoked=>nil }, { :$set=>{ :revoked=>Time.now.utc } })
        end

        # Allows us to kill all pending grants on behalf of client/resource.
        #collection.create_index [[:client_id, Mongo::ASCENDING]]
        #collection.create_index [[:resource, Mongo::ASCENDING]]
      end

    end
  end
end

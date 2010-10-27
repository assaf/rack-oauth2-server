module Rack
  module OAuth2
    module Models

      # Access grant. This is used for authorization code and refresh token.
      # The access grant is a nonce, new grant created each time we need it and
      # good for redeeming one access token.
      class AccessGrant
        class << self
          # Find AccessGrant from authentication code.
          def find(code)
            Models.new_instance self, collection.find_one({ :_id=>code })
          end

          # Create a new access grant.
          def create(account_id, scope, client_id)
            fields = { :_id=>Models.secure_random, :account_id=>account_id, :scope=>scope, :client_id=>client_id,
                       :created_at=>Time.now.utc, :granted_at=>nil, :access_token=>nil, :revoked=>nil }
            collection.insert fields
            Models.new_instance self, fields
          end

          def collection
            Models.db["oauth2.access_grants"]
          end
        end

        # Authorization code. We are nothing without it.
        attr_reader :_id
        alias :code :_id
        # The account on behalf of which we're going to access the resource.
        attr_reader :account_id
        # Client that was granted this access token.
        attr_reader :client_id
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
          access_token = AccessToken.find_or_create(account_id, scope, client_id)
          self.access_token = access_token.token
          self.granted_at = Time.now.utc
          self.class.collection.update({ :_id=>code, :access_token=>nil, :revoked=>nil }, { :$set=>{ :granted_at=>granted_at, :access_token=>access_token.token } }, :safe=>true)
          reload = self.class.collection.find({ :_id=>code }, { :fields=>%w{access_token} })
          raise InvalidGrantError unless reload && reload["access_token"] == access_token.token
          return access_token
        end

        # Allows us to kill all pending grants on behalf of client/account.
        #collection.create_index [[:client_id, Mongo::ASCENDING]]
        #collection.create_index [[:account_id, Mongo::ASCENDING]]
      end

    end
  end
end

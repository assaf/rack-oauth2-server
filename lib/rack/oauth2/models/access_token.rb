module Rack
  module OAuth2
    module Models

      # Access token. This is what clients use to access resources.
      #
      # An access token is a unique code, associated with a client, an account
      # (or user ID) and scope. It may be revoked, or expire after a certain
      # period.
      class AccessToken
        class << self
          # Find AccessToken from token.
          def find(token)
            Models.new_instance self, collection.find_one({ :_id=>token })
          end

          # Create a new access token.
          def create(account_id, scope, client_id)
            fields = { :_id=>Models.secure_random, :account_id=>account_id, :scope=>scope, :client_id=>client_id,
                       :created_at=>Time.now.utc, :expires_at=>nil, :revoked=>false }
            collection.insert fields
            Models.new_instance self, fields
          end

          def collection
            Models.db["oauth2.access_tokens"]
          end
        end

        # Access token. As unique as they come.
        attr_reader :_id
        alias :token :_id
        # The account on behalf of which we're going to access the resource.
        attr_reader :account_id
        # Client that was granted this access token.
        attr_reader :client_id
        # The scope granted in this token.
        attr_reader :scope
        # When token was granted.
        attr_reader :created_at
        # When token expires for good.
        attr_reader :expires_at
        # Timestamp if revoked.
        attr_accessor :revoked

        # Revokes this access token.
        def revoke!
          self.revoked = Time.not.utc
          AccessToken.collection.update({ :_id=>token, :revoked=>false }, { :revoked=>revoked })
        end
        
        # Allows us to kill all pending grants on behalf of client/account.
        #collection.create_index [[:client_id, Mongo::ASCENDING]]
        #collection.create_index [[:account_id, Mongo::ASCENDING]]
      end

    end
  end
end

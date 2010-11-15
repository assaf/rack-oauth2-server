module Rack
  module OAuth2
    class Server

      # Access token. This is what clients use to access resources.
      #
      # An access token is a unique code, associated with a client, an identity
      # and scope. It may be revoked, or expire after a certain period.
      class AccessToken
        class << self

          # Find AccessToken from token. Does not return revoked tokens.
          def from_token(token)
            Server.new_instance self, collection.find_one({ :_id=>token, :revoked=>nil })
          end

          # Get an access token (create new one if necessary).
          def get_token_for(identity, scope, client_id)
            scope = Utils.normalize_scopes(scope)
            client_id = BSON::ObjectId(client_id.to_s)
            unless token = collection.find_one({ :identity=>identity.to_s, :scope=>scope, :client_id=>client_id, :revoked=>nil })
              token = { :_id=>Server.secure_random, :identity=>identity.to_s, :scope=>scope,
                        :client_id=>client_id, :created_at=>Time.now.utc.to_i,
                        :expires_at=>nil, :revoked=>nil }
              collection.insert token
            end
            Server.new_instance self, token
          end

          # Find all AccessTokens for an identity.
          def from_identity(identity)
            collection.find({ :identity=>identity }).map { |fields| Server.new_instance self, fields }
          end

          # Returns all access tokens for a given client, Use limit and offset
          # to return a subset of tokens, sorted by creation date.
          def for_client(client_id, offset = 0, limit = 100)
            client_id = BSON::ObjectId(client_id.to_s)
            collection.find({ :client_id=>client_id }, { :sort=>[[:created_at, Mongo::ASCENDING]], :skip=>offset, :limit=>limit }).
              map { |token| Server.new_instance self, token }
          end

          # Returns count of access tokens.
          #
          # @param [Hash] filter Count only a subset of access tokens
          # @option filter [Integer] days Only count that many days (since now)
          # @option filter [Boolean] revoked Only count revoked (true) or non-revoked (false) tokens; count all tokens if nil
          # @option filter [String, ObjectId] client_id Only tokens grant to this client
          def count(filter = {})
            select = {}
            if filter[:days]
              now = Time.now.utc.to_i
              select[:created_at] = { :$gt=>now - filter[:days] * 86400, :$lte=>now }
            end
            if filter.has_key?(:revoked)
              select[:revoked] = filter[:revoked] ? { :$ne=>nil } : { :$eq=>nil }
            end
            if filter[:client_id]
              select[:client_id] = BSON::ObjectId(filter[:client_id].to_s)
            end
            collection.find(select).count
          end

          def collection
            Server.database["oauth2.access_tokens"]
          end
        end

        # Access token. As unique as they come.
        attr_reader :_id
        alias :token :_id
        # The identity we authorized access to.
        attr_reader :identity
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
          self.revoked = Time.now.utc.to_i
          AccessToken.collection.update({ :_id=>token }, { :$set=>{ :revoked=>revoked } })
        end
        
        Server.create_indexes do
          # Used to revoke all pending access grants when revoking client.
          collection.create_index [[:client_id, Mongo::ASCENDING]]
          # Used to get/revoke access tokens for an identity, also to find and
          # return existing access token.
          collection.create_index [[:identity, Mongo::ASCENDING]]
        end
      end

    end
  end
end

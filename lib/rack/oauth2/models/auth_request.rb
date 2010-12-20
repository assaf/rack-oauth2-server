module Rack
  module OAuth2
    class Server

      # Authorization request. Represents request on behalf of client to access
      # particular scope. Use this to keep state from incoming authorization
      # request to grant/deny redirect.
      class AuthRequest
        class << self
          # Find AuthRequest from identifier.
          def find(request_id)
            id = BSON::ObjectId(request_id.to_s)
            Server.new_instance self, collection.find_one(id)
          rescue BSON::InvalidObjectId
          end

          # Create a new authorization request. This holds state, so in addition
          # to client ID and scope, we need to know the URL to redirect back to
          # and any state value to pass back in that redirect.
          def create(client, scope, redirect_uri, response_type, state)
            scope = Utils.normalize_scope(scope) & client.scope # Only allowed scope
            fields = { :client_id=>client.id, :scope=>scope, :redirect_uri=>client.redirect_uri || redirect_uri,
                       :response_type=>response_type, :state=>state,
                       :grant_code=>nil, :authorized_at=>nil,
                       :created_at=>Time.now.to_i, :revoked=>nil }
            fields[:_id] = collection.insert(fields)
            Server.new_instance self, fields
          end

          def collection
            Server.database["oauth2.auth_requests"]
          end
        end

        # Request identifier. We let the database pick this one out.
        attr_reader :_id
        alias :id :_id
        # Client making this request.
        attr_reader :client_id
        # scope of this request: array of names.
        attr_reader :scope
        # Redirect back to this URL.
        attr_reader :redirect_uri
        # Client requested we return state on redirect.
        attr_reader :state
        # Does what it says on the label.
        attr_reader :created_at
        # Response type: either code or token.
        attr_reader :response_type
        # If granted, the access grant code.
        attr_accessor :grant_code
        # If granted, the access token.
        attr_accessor :access_token
        # Keeping track of things.
        attr_accessor :authorized_at
        # Timestamp if revoked.
        attr_accessor :revoked

        # Grant access to the specified identity.
        def grant!(identity)
          raise ArgumentError, "Must supply a identity" unless identity
          return if revoked
          client = Client.find(client_id) or return
          self.authorized_at = Time.now.to_i
          if response_type == "code" # Requested authorization code
            access_grant = AccessGrant.create(identity, client, scope, redirect_uri)
            self.grant_code = access_grant.code
            self.class.collection.update({ :_id=>id, :revoked=>nil }, { :$set=>{ :grant_code=>access_grant.code, :authorized_at=>authorized_at } })
          else # Requested access token
            access_token = AccessToken.get_token_for(identity, client, scope)
            self.access_token = access_token.token
            self.class.collection.update({ :_id=>id, :revoked=>nil, :access_token=>nil }, { :$set=>{ :access_token=>access_token.token, :authorized_at=>authorized_at } })
          end
          true
        end

        # Deny access.
        def deny!
          self.authorized_at = Time.now.to_i
          self.class.collection.update({ :_id=>id }, { :$set=>{ :authorized_at=>authorized_at } })
        end

        Server.create_indexes do
          # Used to revoke all pending access grants when revoking client.
          collection.create_index [[:client_id, Mongo::ASCENDING]]
        end

      end

    end
  end
end

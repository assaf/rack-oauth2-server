module Rack
  module OAuth2
    class Server
      # A third party that issues assertions
      # http://tools.ietf.org/html/draft-ietf-oauth-assertions-01#section-5.1
      class Issuer
        class << self

          # returns the Issuer object for the given identifier
          def from_identifier(identifier)
            Server.new_instance self, collection.find_one({:_id=>identifier})
          end

          # Create a new Issuer.
          def create(args)
            fields = {}
            [:hmac_secret, :public_key, :notes].each do |key|
              fields[key] = args[key] if args.has_key?(key)
            end
            fields[:created_at] = Time.now.to_i
            fields[:updated_at] = Time.now.to_i
            fields[:_id] = args[:identifier]
            collection.insert(fields, :safe=>true)
            Server.new_instance self, fields
          end


          def collection
            prefix = Server.options[:collection_prefix]
            Server.database["#{prefix}.issuers"]
          end
        end

        # The unique identifier of this Issuer. String or URI
        attr_reader :_id
        alias :identifier :_id
        # shared secret used for verifying HMAC signatures
        attr_reader :hmac_secret
        # public key used for verifying RSA signatures
        attr_reader :public_key
        # notes about this Issuer
        attr_reader :notes


        def update(args)
          fields = [:hmac_secret, :public_key, :notes].inject({}) {|h,k| v = args[k]; h[k] = v if v; h}
          self.class.collection.update({:_id => identifier }, {:$set => fields})
          self.class.from_identifier(identifier)
        end

        Server.create_indexes do
          # Used to revoke all pending access grants when revoking client.
          collection.create_index [[:identifier, Mongo::ASCENDING]]
        end
      end
    end
  end
end

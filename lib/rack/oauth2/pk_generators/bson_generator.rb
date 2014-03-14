module Rack
  module OAuth2
    class BSONGenerator
      class << self
        def from_string(value)
          BSON::ObjectId(value)
        end

        def generate
          BSON::ObjectId.new
        end
      end
    end
  end
end

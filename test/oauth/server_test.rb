require "test/setup"

class ServerTest < Test::Unit::TestCase

  context "setup server" do
    setup { @client = Server.register(:display_name=>"UberClient", :redirect_uri=>"http://uberclient.dot/callback", :scope=>%w{read write oauth-admin}) }
    should "have parameters" do
      assert_equal "http://uberclient.dot/callback", @client.redirect_uri
      assert_equal "UberClient", @client.display_name
      assert_same_elements %w(read write oauth-admin), @client.scope
    end
  end

end

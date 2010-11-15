class << Rails
  def vendor_rails?
    false
  end
end

Rails::Initializer.run do |config|
  config.frameworks = [ :action_controller ]
  config.action_controller.session = { :key=>"_myapp_session", :secret=>"Stay hungry. Stay foolish. -- Steve Jobs" }

  config.after_initialize do
    config.oauth.database = DATABASE
    config.oauth.host = "example.org"
    config.oauth.authenticator = lambda do |username, password|
      "Batman" if username == "cowbell" && password == "more"
    end
  end
  config.middleware.use Rack::OAuth2::Server::Admin.mount
end

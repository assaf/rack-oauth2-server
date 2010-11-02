require "rack/oauth2/rails"

Rails::Initializer.run do |config|
  config.frameworks = [ :action_controller ]
  config.action_controller.session = { :key=>"_myapp_session", :secret=>"Stay hungry. Stay foolish. -- Steve Jobs" }

  config.oauth[:scopes] = %w{read write}
  config.oauth[:authenticator] = lambda do |username, password|
    "Superman" if username == "cowbell" && password == "more"
  end
  config.oauth[:database] = DATABASE
end

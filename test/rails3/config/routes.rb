MyApp::Application.routes.draw do
  # Authorization flow.
  match "oauth/authorize" => "oauth#authorize"
  match "oauth/grant" => "oauth#grant"
  match "oauth/deny" => "oauth#deny"

  # Resources we want to protect
  match ":action"=>"api"

  mount Rack::OAuth2::Server::Admin, :at=>"oauth/admin"

end

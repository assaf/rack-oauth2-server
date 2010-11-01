ActionController::Routing::Routes.draw do |map|
  # Authorization flow.
  map.with_options :controller=>"oauth" do |oauth|
    oauth.connect "oauth/authorize", :action=>"authorize"
    oauth.connect "oauth/grant", :action=>"grant"
    oauth.connect "oauth/deny", :action=>"deny"
  end

  # Resources we want to protect
  map.with_options :controller=>"api" do |api|
    api.connection ":action"
  end
end

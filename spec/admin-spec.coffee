vows = require("vows")
assert = require("assert")
zombie = require("zombie")


vows.describe("Sign In").addBatch(
  "connect":
    topic: ->
      zombie.visit "http://localhost:8080/oauth/admin", @callback
    "should redirect to sign-in page": (browser)-> assert.equal browser.text("button"), "GrantDeny"
    "grant request":
      topic: (browser)->
        browser.pressButton "Grant", @callback
      "should redirect back to oauth admin": (browser)-> assert.equal browser.location, "http://localhost:8080/oauth/admin#/"
      "should be looking at all clients": (browser)-> assert.equal browser.text("title"), "OAuth Admin -  All Clients"
      "should have table with clients": (browser)-> assert.ok browser.html("table.clients")[0]
      "should have one active client": (browser)-> assert.ok browser.html("tr.active").length > 0

).export(module);

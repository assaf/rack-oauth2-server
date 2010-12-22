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
      "active clients":
        topic: (browser)-> browser.querySelectorAll("tr.active").toArray()
        "should include the practice server": (clients)->
          assert.length clients.filter((e)-> e.querySelector(".name").textContent.trim() == "Practice OAuth Console"), 1
        "practice server":
          topic: (clients, browser)->
            clients.filter((e)-> e.querySelector(".name").textContent.trim() == "Practice OAuth Console")[0]
          "name":
            topic: (client)-> client.querySelector(".name")
            "should show service image": (name)->
              assert.ok name.querySelector("img[src='http://localhost:8080/oauth/admin/images/oauth-2.png']")
          "secrets":
            topic: (client)-> client.querySelector(".secrets")
            "should show client ID": (secrets)->
              assert.ok secrets.querySelector("dt:contains('ID') + dd:contains('4d0ee1633321e869ad000001')")
            "should show client secret": (secrets)->
              assert.ok secrets.querySelector("dt:contains('Secret') + dd:contains('74e3f0e33203d79f5e2e404e81daab23929a0112b9bea9afbfff7433bbfaa9cb')")
            "should show redirect URI": (secrets)->
              assert.ok secrets.querySelector("dt:contains('Redirect') + dd:contains('http://localhost:8080/oauth/admin')")

).export(module);

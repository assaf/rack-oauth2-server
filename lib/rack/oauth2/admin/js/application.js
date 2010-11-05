Sammy("#main", function(app) {
  this.use(Sammy.Tmpl);
  this.use(Sammy.Session);
  this.use(Sammy.Title);
  this.setTitle("OAuth Console - ");

  // Use OAuth access token in all API requests.
  $(document).ajaxSend(function(e, xhr) {
    xhr.setRequestHeader("Authorization", "OAuth " + app.session("oauth.token"));
  });
  // For all request (except callback), if we don't have an OAuth access token,
  // ask for one by requesting authorization.
  this.before({ except: { path: /^#(access_token=|[^\\].*&access_token=)/ } }, function(context) {
    if (!app.session("oauth.token"))
      context.redirect("/oauth/admin/authorize?state=" + escape(context.path));
  })
  // We recognize the OAuth authorization callback based on one of its
  // parameters. Crude but works here.
  this.get(/^#(access_token=|[^\\].*&access_token=)/, function(context) {
    // Instead of a hash we get query parameters, so turn those into an object.
    var params = context.path.substring(1).split("&"), args = {};
    for (var i in params) {
      var splat = params[i].split("=");
      args[splat[0]] = splat[1];
    }
    app.session("oauth.token", args.access_token);
    // When the filter redirected the original request, it passed the original
    // request's URL in the state parameter, which we get back after
    // authorization.
    context.redirect(args.state.length == 0 ? "#/" : unescape(args.state));
  });


  // View all clients
  this.get("#/", function(context) {
    context.title("All Clients");
    $.getJSON("/oauth/admin/api/clients", function(json) {
      clients = json.list;
      context.partial("/oauth/admin/views/clients.tmpl", { clients: clients, tokens: json.tokens });
    });
  });
  // View single client
  this.get("#/client/:id", function(context) {
    $.getJSON("/oauth/admin/api/client/" + context.params.id, function(client) {
      context.title(client.displayName);
      context.partial("/oauth/admin/views/client.tmpl", client)
    })
  });
  // Edit client
  this.get("#/client/:id/edit", function(context) {
    $.getJSON("/oauth/admin/api/client/" + context.params.id, function(client) {
      context.title(client.displayName);
      context.partial("/oauth/admin/views/edit.tmpl", client)
    })
  });
  this.put("#/client/:id", function(context) {
    $.ajax({ type: "put", url: "/oauth/admin/api/client/" + context.params.id,
      data: {
        displayName: context.params.displayName,
        link: context.params.link,
        redirectUri: context.params.redirectUri,
        imageUrl: context.params.imageUrl
      },
      success: function(client) {
        context.redirect("#/client/" + context.params.id);
        app.trigger("notice", "Saved your changes");
      },
      error: function(xhr) {
        context.partial("/oauth/admin/views/edit.tmpl", context.params);
        app.trigger("notice", xhr.responseText);
      }
    })
  });
  // Create new client
  this.get("#/new", function(context) {
    context.title("Add New Client");
    context.partial("/oauth/admin/views/edit.tmpl", context.params);
  });
  this.post("#/clients", function(context) {
    context.title("Add New Client");
    $.ajax({ type: "post", url: "/oauth/admin/api/clients",
      data: {
        displayName: context.params.displayName,
        link: context.params.link,
        redirectUri: context.params.redirectUri,
        imageUrl: context.params.imageUrl
      },
      success: function(client) {
        app.trigger("notice", "Added new client application " + client.displayName);
        context.redirect("#/");
      },
      error: function(xhr) {
        app.trigger("notice", xhr.responseText);
        context.partial("/oauth/admin/views/edit.tmpl", context.params);
      }
    });
  });

  // Client/token revoke buttons do this.
  $("a[data-method=post]").live("click", function(evt) {
    evt.preventDefault();
    var link = $(this);
    if (link.attr("data-confirm") && !confirm(link.attr("data-confirm")))
      return;
    $.post(link.attr("href"), function(success) {
      app.trigger("notice", "Revoked!");
      app.refresh();
    });
  });
  // Link to reveal/hide client ID/secret
  $("td.secrets a[rel=toggle]").live("click", function(evt) {
    evt.preventDefault();
    var dl = $(this).next("dl");
    if (dl.is(":visible")) {
      $(this).html("Reveal");
      dl.hide();
    } else {
      $(this).html("Hide");
      dl.show();
    }
  });
  // Error/notice at top of screen
  var noticeTimeout;
  app.bind("notice", function(evt, message) {
    $("#notice").text(message).fadeIn("fast");
    if (noticeTimeout) {
      cancelTimeout(noticeTimeout);
      noticeTimeout = null;
    }
    noticeTimeout = setTimeout(function() {
      noticeTimeout = null;
      $("#notice").fadeOut("slow");
    }, 5000);
  });
  $("#notice").live("click", function() { $(this).fadeOut("slow") });
});

// Adds thousands separator to integer or float (can also pass formatted string
// if you care about precision).
$.thousands = function(integer) {
  return integer.toString().replace(/^(\d+?)((\d{3})+)$/g, function(x,a,b) { return a + b.replace(/(\d{3})/g, ",$1") })
    .replace(/\.((\d{3})+)(\d+)$/g, function(x,a,b,c) { return "." + a.replace(/(\d{3})/g, "$1,") + c })
}

$.shortdate = function(integer) {
  var date = new Date(integer * 1000);
  return "<span title='" + date.toLocaleString() + "'>" + date.toISOString().substring(0,10) + "</span>";
}

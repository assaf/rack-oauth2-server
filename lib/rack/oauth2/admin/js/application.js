Sammy("#main", function(app) {
  this.use(Sammy.Tmpl);
  this.use(Sammy.Session);
  this.use(Sammy.Title);
  this.setTitle("OAuth Console - ");
  this.use(Sammy.OAuth2);
  this.authorize = document.location.pathname + "/authorize";

  $(document).ajaxError(function(evt, xhr) { app.trigger("notice", xhr.responseText); });
  $(document).ajaxStart(function(evt) { $("#throbber").show(); });
  $(document).ajaxStop(function(evt) { $("#throbber").hide(); });

  // For all request (except callback), if we don't have an OAuth access token,
  this.requireOAuth();
  this.bind("oauth.denied", function(evt, error) {
    this.partial("admin/views/no_access.tmpl", { error: error.message });
  });

  var api = document.location.pathname + "/api";
  // View all clients
  this.get("#/", function(context) {
    context.title("All Clients");
    $.getJSON(api + "/clients", function(json) {
      context.partial("admin/views/clients.tmpl", { clients: json.list, tokens: json.tokens });
    });
  });
  // Edit client
  this.get("#/client/:id/edit", function(context) {
    $.getJSON(api + "/client/" + context.params.id, function(client) {
      context.title(client.displayName);
      context.partial("admin/views/edit.tmpl", client)
    })
  });
  this.put("#/client/:id", function(context) {
    $.ajax({ type: "put", url: api + "/client/" + context.params.id,
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
      error: function(xhr) { context.partial("admin/views/edit.tmpl", context.params); }
    })
  });
  // Delete/revoke client
  this.del("#/client/:id", function(context) {
    $.ajax({ type: "post", url: api + "/client/" + context.params.id,
      data: { _method: "delete" },
      success: function() { context.redirect("#/") }
    });
  });
  this.post("#/client/:id/revoke", function(context) {
    $.post(api + "/client/" + context.params.id + "/revoke", function() { app.refresh() });
  });
  // Revoke token
  this.post("#/token/:id/revoke", function(context) {
    $.post(api + "/token/" + context.params.id + "/revoke", function() { app.refresh() });
  });
  // View single client
  this.get("#/client/:id", function(context) {
    $.getJSON(api + "/client/" + context.params.id, function(client) {
      context.title(client.displayName);
      context.partial("admin/views/client.tmpl", client)
    });
  });
  this.get("#/client/:id/:page", function(context) {
    $.getJSON(api + "/client/" + context.params.id + "?page=" + context.params.page, function(client) {
      context.title(client.displayName);
      context.partial("admin/views/client.tmpl", client)
    });
  });
  // Create new client
  this.get("#/new", function(context) {
    context.title("Add New Client");
    context.partial("admin/views/edit.tmpl", context.params);
  });
  this.post("#/clients", function(context) {
    context.title("Add New Client");
    $.ajax({ type: "post", url: api + "/clients",
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
      error: function(xhr) { context.partial("admin/views/edit.tmpl", context.params); }
    });
  });
  // Signout
  this.get("#/signout", function(context) {
    context.loseAccessToken();
    context.redirect("#/");
  });

  // Links that use forms for various methods (i.e. post, delete).
  $("a[data-method]").live("click", function(evt) {
    evt.preventDefault();
    var link = $(this);
    if (link.attr("data-confirm") && !confirm(link.attr("data-confirm")))
      return fasle;
    var method = link.attr("data-method") || "get",
        form = $("<form>", { style: "display:none", method: method, action: link.attr("href") });
    app.$element().append(form);
    form.submit();
  });
  // Error/notice at top of screen
  var noticeTimeout;
  app.bind("notice", function(evt, message) {
    if (!message || message.trim() == "")
      message = "Got an error, but don't know why";
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

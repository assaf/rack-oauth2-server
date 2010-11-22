Sammy("#main", function(app) {
  this.use(Sammy.Tmpl);
  this.use(Sammy.Session);
  this.use(Sammy.Title);
  this.setTitle("OAuth Admin - ");
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
  this.bind("oauth.connected", function() { $("#header .signout").show(); });
  this.bind("oauth.disconnected", function() { $("#header .signout").hide(); });

  var api = document.location.pathname + "/api";
  // Takes array of string with scope names (typically request parameters) and
  // normalizes them into an array of scope names.
  function mergeScope(scope) {
    if ($.isArray(scope))
      scope = scope.join(" ");
    scope = (scope || "").trim().split(/\s+/);
    return scope.length == 1 && scope[0] === "" ? [] : _.uniq(scope).sort();
  }
  var commonScope;
  function withCommonScope(cb) {
    if (commonScope)
      cb(commonScope);
    else
      $.getJSON(api + "/clients", function(json) { cb(commonScope = json.scope); });
  }

  // View all clients
  this.get("#/", function(context) {
    context.title("All Clients");
    $.getJSON(api + "/clients", function(clients) {
      commonScope = clients.scope;
      context.partial("admin/views/clients.tmpl", { clients: clients.list, tokens: clients.tokens }).
        load(clients.history).then(function(json) { $("#fig").chart(json.data, "granted"); });
    });
  });
  // View single client
  this.get("#/client/:id", function(context) {
    $.getJSON(api + "/client/" + context.params.id, function(client) {
      context.title(client.displayName);
      client.notes = (client.notes || "").split(/\n\n/);
      context.partial("admin/views/client.tmpl", client).
        load(client.history).then(function(json) { $("#fig").chart(json.data, "granted"); });
    });
  });
  this.get("#/client/:id/page/:page", function(context) {
    $.getJSON(api + "/client/" + context.params.id + "?page=" + context.params.page, function(client) {
      context.title(client.displayName);
      client.notes = client.notes.split(/\n\n/);
      context.partial("admin/views/client.tmpl", client).
        load(client.history).then(function(json) { $("#fig").chart(json.data, "granted"); });
    });
  });
  // Edit client
  this.get("#/client/:id/edit", function(context) {
    $.getJSON(api + "/client/" + context.params.id, function(client) {
      context.title(client.displayName);
      withCommonScope(function(scope) {
        client.common = scope;
        context.partial("admin/views/edit.tmpl", client);
      });
    });
  });
  this.put("#/client/:id", function(context) {
    context.params.scope = mergeScope(context.params.scope);
    $.ajax({ type: "put", url: api + "/client/" + context.params.id,
      data: {
        displayName: context.params.displayName,
        link: context.params.link,
        imageUrl: context.params.imageUrl,
        redirectUri: context.params.redirectUri,
        notes: context.params.notes,
        scope: context.params.scope
      },
      success: function(client) {
        context.redirect("#/client/" + context.params.id);
        app.trigger("notice", "Saved your changes");
      },
      error: function(xhr) {
        withCommonScope(function(scope) {
          context.params.common = scope;
          context.partial("admin/views/edit.tmpl", context.params);
        });
      }
    });
  });
  // Delete/revoke client
  this.del("#/client/:id", function(context) {
    $.ajax({ type: "post", url: api + "/client/" + context.params.id,
      data: { _method: "delete" },
      success: function() { context.redirect("#/"); }
    });
  });
  this.post("#/client/:id/revoke", function(context) {
    $.post(api + "/client/" + context.params.id + "/revoke", function() { app.refresh(); });
  });
  // Revoke token
  this.post("#/token/:id/revoke", function(context) {
    $.post(api + "/token/" + context.params.id + "/revoke", function() { app.refresh(); });
  });
  // Create new client
  this.get("#/new", function(context) {
    context.title("Add New Client");
    withCommonScope(function(scope) {
      context.partial("admin/views/edit.tmpl", { common: scope, scope: scope });
    });
  });
  this.post("#/clients", function(context) {
    context.title("Add New Client");
    context.params.scope = mergeScope(context.params.scope);
    $.ajax({ type: "post", url: api + "/clients",
      data: {
        displayName: context.params.displayName,
        link: context.params.link,
        imageUrl: context.params.imageUrl,
        redirectUri: context.params.redirectUri,
        notes: context.params.notes,
        scope: context.params.scope
      },
      success: function(client) {
        app.trigger("notice", "Added new client application " + client.displayName);
        context.redirect("#/");
      },
      error: function(xhr) {
        withCommonScope(function(scope) {
          context.params.common = scope;
          context.partial("admin/views/edit.tmpl", context.params);
        });
      }
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
      return false;
    var method = link.attr("data-method") || "get",
        form = $("<form>", { style: "display:none", method: method, action: link.attr("href") });
    app.$element().append(form);
    form.submit();
    return false;
  });
  // Error/notice at top of screen
  var noticeTimeout;
  app.bind("notice", function(evt, message) {
    if (!message || message.trim() === "")
      message = "Got an error, but don't know why";
    $("#notice").text(message).fadeIn("fast");
    if (noticeTimeout) {
      clearTimeout(noticeTimeout);
      noticeTimeout = null;
    }
    noticeTimeout = setTimeout(function() {
      noticeTimeout = null;
      $("#notice").fadeOut("slow");
    }, 5000);
  });
  $("#notice").live("click", function() { $(this).fadeOut("slow"); });
});

// Adds thousands separator to integer or float (can also pass formatted string
// if you care about precision).
$.thousands = function(integer) {
  return integer.toString().replace(/^(\d+?)((\d{3})+)$/g, function(x,a,b) { return a + b.replace(/(\d{3})/g, ",$1"); }).
    replace(/\.((\d{3})+)(\d+)$/g, function(x,a,b,c) { return "." + a.replace(/(\d{3})/g, "$1,") + c; });
};

$.shortdate = function(integer) {
  var date = new Date(integer * 1000);
  return "<span title='" + date.toLocaleString() + "'>" + date.toDateString().substring(0,10) + "</span>";
};

$.fn.chart = function(data, series) {
  /* Sizing and scales. */
  var canvas = $(this),
      w = canvas.width(), h = canvas.height(),
      today = new Date() / 86400000,
      x = pv.Scale.linear(today - 60, today).range(0, w),
      max = pv.max(data, function(d) { return d[series]; }),
      y = pv.Scale.linear(0, pv.max([max, 10])).range(0, h);

  /* The root panel. */
  var vis = new pv.Panel().width(w).height(h).bottom(20).left(20).right(10).top(5);
  /* X-axis ticks. */
  vis.add(pv.Rule).data(x.ticks()).visible(function(d) { return d > 0; }).left(x).strokeStyle("#fff").
    add(pv.Rule).bottom(-5).height(5).strokeStyle("#000").
    anchor("bottom").add(pv.Label).text(function(d) { return pv.Format.date("%b %d").format(new Date(d * 86400000)); }); 
  /* Y-axis ticks. */
  vis.add(pv.Rule).data(y.ticks(3)).bottom(y).strokeStyle(function(d) { return d ? "#fff" : "#000"; }).
    anchor("left").add(pv.Label).text(y.tickFormat);
  /* The line. */
  vis.add(pv.Line).data(data).interpolate("linear").left(function(d) { return x(new Date(d.ts)); }).bottom(function(d) { return y(d[series]); }).lineWidth(3);
  vis.canvas(canvas[0]).render();
};

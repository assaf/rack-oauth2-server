Sammy "#main", (app) ->
  @.use Sammy.Tmpl
  @.use Sammy.Session
  @.use Sammy.Title
  @.setTitle "OAuth Admin - "
  @.use Sammy.OAuth2
  @.authorize = document.location.pathname + "/authorize"

  # All XHR errors we don't catch explicitly handled here
  $(document).ajaxError (evt, xhr)->
    if xhr.status == 401
      app.loseAccessToken()
    app.trigger("notice", xhr.responseText)
  # Show something when XHR request in progress
  $(document).ajaxStart (evt)-> $("#throbber").show()
  $(document).ajaxStop (evt)-> $("#throbber").hide()

  @.requireOAuth()
  # Show error message if access denied
  @bind "oauth.denied", (evt, error)-> 
    app.partial("admin/views/no_access.tmpl", { error: error.message })
  # Show signout link if authenticated, hide if not
  @.bind "oauth.connected", ()->
    $("#header .signin").hide()
    $("#header .signout").show()
  @.bind "oauth.disconnected", ()->
    $("#header .signin").show()
    $("#header .signout").hide()

  api = "#{document.location.pathname}/api"
  # Takes array of string with scope names (typically request parameters) and
  # normalizes them into an array of scope names.
  mergeScope = (scope) ->
    if $.isArray(scope)
      scope = scope.join(" ")
    scope = (scope || "").trim().split(/\s+/)
    if scope.length == 1 && scope[0] == "" then [] else _.uniq(scope).sort()
  commonScope = null
  # Run callback with list of common scopes. First time, make an API call to
  # retrieve that list and cache is in memory, since it rarely changes.
  withCommonScope = (cb) ->
    if commonScope
      cb commonScope
    else
      $.getJSON "#{api}/clients", (json)-> cb(commonScope = json.scope)

  # View all clients
  @.get "#/", (context)->
    context.title "All Clients"
    $.getJSON "#{api}/clients", (clients)->
      commonScope = clients.scope
      context.partial("admin/views/clients.tmpl", { clients: clients.list, tokens: clients.tokens }).
        load(clients.history).
        then( (json)-> $("#fig").chart(json.data, "granted") )

  # View single client
  @.get "#/client/:id", (context)->
    $.getJSON "#{api}/client/#{context.params.id}", (client)->
      context.title client.displayName
      client.notes = (client.notes || "").split(/\n\n/)
      context.partial("admin/views/client.tmpl", client).
        load(client.history).then((json)-> $("#fig").chart(json.data, "granted"))
  # With pagination
  @.get "#/client/:id/page/:page", (context)->
    $.getJSON "#{api}/client/#{context.params.id}?page=#{context.params.page}", (client)->
      context.title client.displayName
      client.notes = client.notes.split(/\n\n/)
      context.partial("admin/views/client.tmpl", client).
        load(client.history).then((json)-> $("#fig").chart(json.data, "granted"))

  # Revoke token
  @.post "#/token/:id/revoke", (context)->
    $.post "#{api}/token/#{context.params.id}/revoke", ()->
      context.redirect "#/"

  # Edit client
  @.get "#/client/:id/edit", (context)->
    $.getJSON "#{api}/client/#{context.params.id}", (client)->
      context.title client.displayName
      withCommonScope (scope)->
        client.common = scope
        context.partial "admin/views/edit.tmpl", client
  @.put "#/client/:id", (context)->
    context.params.scope = mergeScope(context.params.scope)
    $.ajax
      type: "put"
      url: "#{api}/client/#{context.params.id}"
      data:
        displayName: context.params.displayName
        link: context.params.link
        imageUrl: context.params.imageUrl
        redirectUri: context.params.redirectUri
        notes: context.params.notes
        scope: context.params.scope
      success: (client)->
        context.redirect "#/client/#{context.params.id}"
        app.trigger "notice", "Saved your changes"
      error: (xhr)->
        withCommonScope (scope)->
          context.params.common = scope
          context.partial "admin/views/edit.tmpl", context.params

  # Delete client
  @.del "#/client/:id", (context)->
    $.ajax
      type: "post"
      url: "#{api}/client/#{context.params.id}"
      data: { _method: "delete" }
      success: ()-> context.redirect("#/")

  # Revoke client
  @.post "#/client/:id/revoke", (context)->
    $.post "#{api}/client/#{context.params.id}/revoke", ()->
      context.redirect "#/"

  # Create new client
  @.get "#/new", (context)->
    context.title "Add New Client"
    withCommonScope (scope)->
      context.partial "admin/views/edit.tmpl", { common: scope, scope: scope }
  @.post "#/clients", (context)->
    context.title "Add New Client"
    context.params.scope = mergeScope(context.params.scope)
    $.ajax
      type: "post"
      url: "#{api}/clients"
      data:
        displayName: context.params.displayName
        link: context.params.link
        imageUrl: context.params.imageUrl
        redirectUri: context.params.redirectUri
        notes: context.params.notes
        scope: context.params.scope
      success: (client)->
        app.trigger "notice", "Added new client application #{client.displayName}"
        context.redirect "#/"
      error: (xhr)->
        withCommonScope (scope)->
          context.params.common = scope
          context.partial "admin/views/edit.tmpl", context.params

  # Signout
  @.get "#/signout", (context)->
    context.loseAccessToken()
    context.redirect "#/"

  # Links that use forms for various methods (i.e. post, delete).
  $("a[data-method]").live "click", (evt)->
    evt.preventDefault
    link = $(this)
    if link.attr("data-confirm") && !confirm(link.attr("data-confirm"))
      return false
    method = link.attr("data-method") || "get"
    form = $("<form>", { style: "display:none", method: method, action: link.attr("href") })
    if method != "get" && method != "post"
      form.append($("<input name='_method' type='hidden' value='#{method}'>"))
    app.$element().append form
    form.submit()
    false

  # Error/notice at top of screen
  noticeTimeout = null
  app.bind "notice", (evt, message)->
    if !message || message.trim() == ""
      message = "Got an error, but don't know why"
    $("#notice").text(message).fadeIn("fast")
    if noticeTimeout
      clearTimeout noticeTimeout
      noticeTimeout = null
    noticeTimeout = setTimeout ()->
      noticeTimeout = null
      $("#notice").fadeOut("slow")
    , 5000
  $("#notice").live "click", ()-> $(@).fadeOut("slow")


# Adds thousands separator to integer or float (can also pass formatted string
# if you care about precision).
$.thousands = (integer)->
  integer.toString().replace(/^(\d+?)((\d{3})+)$/g, (x,a,b)-> a + b.replace(/(\d{3})/g, ",$1") ).
    replace(/\.((\d{3})+)(\d+)$/g, (x,a,b,c)-> "." + a.replace(/(\d{3})/g, "$1,") + c )

# Returns abbr element with short form of the date (e.g. "Nov 21 2010"). THe
# title attribute provides the full date/time instance, so you can see more
# details by hovering over the element.
$.shortdate = (integer)->
  date = new Date(integer * 1000)
  "<abbr title='#{date.toLocaleString()}'>#{date.toDateString().substring(0,10)}</abbr>"

# Draw chart inside the specified container element.
# data -- Array of objects, each one having a timestamp (ts) and some value we
# want to chart
# series -- Name of the value we want to chart
$.fn.chart = (data, series)->
  return if typeof pv == "undefined" # no PV in test environment
  canvas = $(@)
  w = canvas.width()
  h = canvas.height()
  today = Math.floor(new Date() / 86400000)
  x = pv.Scale.linear(today - 60, today + 1).range(0, w)
  max = pv.max(data, (d)-> d[series])
  y = pv.Scale.linear(0, pv.max([max, 10])).range(0, h)

  # The root panel.
  vis = new pv.Panel().width(w).height(h).bottom(20).left(20).right(10).top(5)
  # X-axis ticks.
  vis.add(pv.Rule).data(x.ticks()).left(x).strokeStyle("#fff").
    add(pv.Rule).bottom(-5).height(5).strokeStyle("#000").
    anchor("bottom").add(pv.Label).text((d)-> pv.Format.date("%b %d").format(new Date(d * 86400000)) )
  # Y-axis ticks.
  vis.add(pv.Rule).data(y.ticks(3)).bottom(y).strokeStyle((d)-> if d then "#ddd" else "#000").
    anchor("left").add(pv.Label).text(y.tickFormat)
  # If we only have one data point, can't show a line so show dot instead
  if data.length == 1
    vis.add(pv.Dot).data(data).
      left((d)-> x(new Date(d.ts)) ).bottom((d)-> y(d[series])).radius(3).lineWidth(2)
  else
    vis.add(pv.Line).data(data).interpolate("linear").
      left((d)-> x(new Date(d.ts)) ).bottom((d)-> y(d[series]) ).lineWidth(3)
  vis.canvas(canvas[0]).render()

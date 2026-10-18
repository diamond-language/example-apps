# Stash: private bookmarks on Gremlin (server), Div (views) and Mjolnir (data).
# Requests flow through lib/web.di's pipeline: guards, then a handler that
# calls Accounts / Bookmarks. Views are pure functions of that data.
require_cut "gremlin"
require_cut "div"
require_cut "mjolnir"
require_cut "cookies"
require "./lib/util"
require "./views/.cache/layout.html"
require "./views/.cache/welcome.html"
require "./views/.cache/errors.html"
require "./views/.cache/login.html"
require "./views/.cache/signup.html"
require "./views/.cache/index.html"
require "./views/.cache/bookmark_form.html"
require "./lib/web"
require "./lib/auth"
require "./lib/guards"
require "./lib/pages"
require "./lib/changesets"
require "./lib/accounts"
require "./lib/schema"
require "./lib/bookmarks"
require "./lib/handlers"

# Each gremlin worker is an isolated VM, so a worker builds its own database
# handle, repo and router on its first request and keeps them in its context.
def build_state()
  db = SQLite3.open(ENV["STASH_DB"] || "data/stash.db")
  db.execute("PRAGMA foreign_keys = ON")
  repo = Mjolnir::Repo.new(db)
  schemas = Schemas.new()

  assets = {
    "/css/app.css": ["text/css", File.read("public/css/app.css")]
  }

  csrf = [require_authentication, require_csrf]
  router = Web::Router.new()
  router.get("/", BookmarkPages.index)
  router.get("/signup", AccountPages.signup_form)
  router.post("/signup", AccountPages.signup)
  router.get("/login", AccountPages.login_form)
  router.post("/login", AccountPages.login)
  router.post("/logout", AccountPages.logout, csrf)
  router.get("/bookmarks/new", BookmarkPages.new_form, [require_authentication])
  router.post("/bookmarks", BookmarkPages.create, csrf)
  router.get("/bookmarks/:id/edit", BookmarkPages.edit_form, [require_authentication])
  router.post("/bookmarks/:id/delete", BookmarkPages.destroy, csrf)
  router.post("/bookmarks/:id", BookmarkPages.update, csrf)
  {"router": router, "assets": assets, "repo": repo, "schemas": schemas}
end

def state_for(context)
  state = context["state"]
  if state == nil
    state = build_state()
    context["state"] = state
  end
  state
end

def handler(request, context)
  state = state_for(context)
  asset = state["assets"][request["path"]]
  if asset != nil && request["method"] == "GET"
    return [200, {"Content-Type": asset[0]}, asset[1]]
  end
  conn = Web::Conn.new(request)
  conn.repo = state["repo"]
  conn.schemas = state["schemas"]
  Auth.load(conn)
  response = state["router"].dispatch(conn)
  Auth.finish(conn, response)
end

gremlin_serve((ENV["PORT"] || "18300").to_i(), handler, (ENV["STASH_THREADS"] || "1").to_i())

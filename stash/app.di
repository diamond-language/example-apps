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

# Stop with the fix named, rather than serve an old page, if a template changed since compile_views.sh ran.
Div.check_fresh("views", "./compile_views.sh")

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

# Opens the database before serving (workers open it lazily, per request), so a
# fresh checkout starts with the schema in place instead of failing on the first request.
def prepare_database(path)
  dir = File.dirname(path)
  if !File.directory?(dir) then Dir.mkdir(dir) end
  db = SQLite3.open(path)
  if db.query("SELECT name FROM sqlite_master WHERE name = 'users'").length() == 0
    File.read("db/schema.sql").split(";").each() do |statement|
      if statement.split("\n").any?() do |line| line.strip() != "" && !line.strip().start_with?("--") end
        db.execute(statement)
      end
    end
    puts("created #{path} from db/schema.sql")
  end
  db.close()
end

db_path = ENV["STASH_DB"] || "data/stash.db"
port = (ENV["PORT"] || "18300").to_i()
threads = (ENV["STASH_THREADS"] || "1").to_i()
prepare_database(db_path)
puts("Stash listening on http://127.0.0.1:#{port} (database #{db_path}, #{threads} worker#{threads == 1 ? "" : "s"}); Ctrl+C to stop")
gremlin_serve(port, handler, threads)

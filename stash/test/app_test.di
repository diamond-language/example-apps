# End-to-end test: accounts, sessions, CSRF, bookmark CRUD, tags, search, paging and privacy,
# against a real server on a throwaway database. Run it with `bash test.sh`.
require_cut "minitest"
require "../lib/util"

# A small HTTP client that keeps cookies the way a browser would.
class Client
  attr_reader cookies: Hash

  def initialize(port: Int)
    @port = port
    @cookies = {}
  end

  # Returns [status, location, body].
  def request(method: String, path: String, form: Hash | Nil = nil) -> Array
    body = form == nil ? "" : form.keys().map() do |key| "#{url_encode(key)}=#{url_encode(form[key])}" end.join("&")
    lines = ["#{method} #{path} HTTP/1.1", "Host: 127.0.0.1", "Connection: close"]
    if @cookies.length() > 0
      lines.push("Cookie: " + @cookies.keys().map() do |name| "#{name}=#{@cookies[name]}" end.join("; "))
    end
    if form != nil
      lines.push("Content-Type: application/x-www-form-urlencoded")
      lines.push("Content-Length: #{body.bytesize()}")
    end
    conn = TCPSocket.connect("127.0.0.1", @port)
    conn.write(lines.join("\r\n") + "\r\n\r\n" + body)
    conn.flush()
    reply = StringBuilder.new()
    chunk = conn.read(4096)
    while chunk != nil && chunk.length() > 0
      reply.append(chunk)
      chunk = conn.read(4096)
    end
    conn.close()
    parse(reply.to_s())
  end

  private def parse(reply: String) -> Array
    split_at = reply.index("\r\n\r\n")
    head = reply.slice(0, split_at).split("\r\n")
    location = nil
    head.drop(1).each() do |line|
      name = line.split(":")[0].downcase()
      value = line.slice(name.length() + 1, line.length()).strip()
      if name == "location" then location = value end
      if name == "set-cookie" then keep_cookie(value) end
    end
    [head[0].split(" ")[1].to_i(), location, reply.slice(split_at + 4, reply.length())]
  end

  private def keep_cookie(value: String)
    pair = value.split(";")[0]
    name = pair.split("=")[0]
    if value.include?("Max-Age=0")
      @cookies.delete(name)
    else
      @cookies[name] = pair.slice(name.length() + 1, pair.length())
    end
  end
end

def csrf_from(html: String)
  match = Regexp.new("name=\"csrf_token\" value=\"([0-9a-f]+)\"").match(html)
  match == nil ? nil : match[1]
end

def occurrences(text: String, needle: String) -> Int = text.split(needle).length() - 1

def check(name: String, ok: Bool, detail = nil)
  Minitest.assert(ok, detail == nil ? name : "#{name}: #{detail.inspect()}")
end

def run_tests()
  port = 18391
  scratch = Process.run(["mktemp", "-d"]).stdout().strip()
  log = File.join(scratch, "server.log")
  db_path = File.join(scratch, "t.db")
  server = Process.spawn([ENV["DIAMOND_BIN"] || "diamond", "app.di"], {
    "env": {"STASH_DB": db_path, "PORT": port.to_s(), "STASH_SESSION_SECRET": "test-secret-test-secret-test-secret"},
    "stdout": log,
    "stderr_to_stdout": true
  })

  # The app creates the database from db/schema.sql, then starts listening.
  up = false
  tries = 0
  pause = Channel.new(1)
  while !up && tries < 300
    begin
      Client.new(port).request("GET", "/css/app.css")
      up = true
    rescue error: IOError
      tries += 1
      pause.wait_readable([], Time.monotonic() + 0.1)
    end
  end
  if !up
    puts("server never came up; see #{log}")
    server.terminate()
    exit(1)
  end

  def sql(query: String, args: Array = []) -> Array
    db = SQLite3.open(db_path)
    rows = db.query(query, args)
    db.close()
    rows
  end

  # The tests run in order and share these, as one person's visit would.
  ada = Client.new(port)
  state = {}

  def test_anonymous()
    [s, _, html] = ada.request("GET", "/")
    check("anonymous home is the welcome page", s == 200 && html.include?("Keep the links worth keeping"), s)
    [s, loc, _] = ada.request("GET", "/bookmarks/new")
    check("add form needs sign-in", s == 302 && loc == "/login", [s, loc])
    [s, _, _] = ada.request("POST", "/bookmarks", {"url": "https://x.example"})
    check("create without a session is refused", s == 302 || s == 403, s)
  end

  def test_signup()
    [s, _, html] = ada.request("POST", "/signup", {"email": "x", "username": "a", "password": "short"})
    check("bad signup is 422 with messages", s == 422 && html.include?("email is invalid") && html.include?("password is too short"), s)
    [s, loc, _] = ada.request("POST", "/signup", {"email": "ada@example.com", "username": "ada", "password": "correct horse"})
    check("signup signs in", s == 302 && loc == "/" && ada.cookies().has_key?("session_token"), [s, loc])
    [_, _, html] = ada.request("GET", "/")
    check("home shows flash, empty state and username", html.include?("Welcome to Stash") && html.include?("Nothing saved yet") && html.include?("@ada"))
    token = csrf_from(html)
    check("layout carries a CSRF token", token != nil && token.length() == 64, token)
    state["token"] = token
    [s, _, html] = ada.request("POST", "/signup", {"email": "ada@example.com", "username": "other", "password": "correct horse"})
    check("duplicate email rejected", s == 422 && html.include?("email has already been taken"), s)
  end

  def test_create()
    token = state["token"]
    [s, _, body] = ada.request("POST", "/bookmarks", {"url": "https://ruby-lang.org", "title": "Ruby"})
    check("create without CSRF is 403", s == 403 && body == "invalid CSRF token", [s, body])
    [s, _, html] = ada.request("POST", "/bookmarks", {"csrf_token": token, "url": "ftp://nope", "title": "x"})
    check("non-http url rejected", s == 422 && html.include?("must start with http"), s)
    [s, _, html] = ada.request("POST", "/bookmarks", {"csrf_token": token, "url": "", "title": ""})
    check("blank url rejected", s == 422 && html.include?("url is required"), s)
    [s, loc, _] = ada.request("POST", "/bookmarks", {"csrf_token": token, "url": "https://ruby-lang.org", "title": "Ruby", "note": "the language", "tags": "Ruby, Lang  ruby"})
    check("create redirects home", s == 302 && loc == "/", [s, loc])
    ada.request("POST", "/bookmarks", {"csrf_token": token, "url": "https://example.com/a?b=1&c=2", "title": "", "tags": "web"})
    rows = sql("select title, tags from bookmarks order by id")
    check("tags normalized and deduplicated", rows[0]["tags"] == " ruby lang ", rows)
    check("blank title defaults to the url", rows[1]["title"] == "https://example.com/a?b=1&c=2", rows)
    [_, _, html] = ada.request("GET", "/")
    check("list shows both, escaped", html.include?("Ruby") && html.include?("the language") && html.include?("b=1&amp;c=2") && html.include?("Bookmark saved"))
    check("a blank note renders nothing", !html.include?(">nil<") && occurrences(html, "class=\"note\"") == 1)
    check("tag sidebar counts", html.include?("href=\"/?tag=ruby\"") && html.include?("href=\"/?tag=web\""))
  end

  def test_search()
    [_, _, html] = ada.request("GET", "/?q=language")
    check("search by note", html.include?("ruby-lang.org") && !html.include?("example.com") && html.include?("1 result for"))
    [_, _, html] = ada.request("GET", "/?tag=web")
    check("filter by tag", html.include?("example.com") && !html.include?("ruby-lang.org") && html.include?("tagged"))
    [_, _, html] = ada.request("GET", "/?tag=ruby&q=nothing-matches")
    check("no match message", html.include?("No bookmarks match"))
    [_, _, html] = ada.request("GET", "/?q=%3Cscript%3E")
    check("search term is escaped", !html.include?("<script>") && html.include?("&lt;script&gt;"))
  end

  def test_edit()
    token = state["token"]
    id = sql("select id from bookmarks order by id limit 1")[0]["id"]
    state["id"] = id
    [s, _, html] = ada.request("GET", "/bookmarks/#{id}/edit")
    check("edit form prefilled", s == 200 && html.include?("value=\"https://ruby-lang.org\"") && html.include?("ruby lang"), s)
    [s, _, _] = ada.request("POST", "/bookmarks/#{id}", {"csrf_token": token, "url": "https://ruby-lang.org", "title": "", "note": "", "tags": "x"})
    check("a blank title on update falls back to the url", s == 302, s)
    [s, _, html] = ada.request("POST", "/bookmarks/#{id}", {"csrf_token": token, "url": "nope", "title": "t"})
    check("update rejects a bad url", s == 422 && html.include?("must start with http"), s)
    ada.request("POST", "/bookmarks/#{id}", {"csrf_token": token, "url": "https://ruby-lang.org/en", "title": "Ruby home", "note": "n", "tags": "ruby"})
    row = sql("select url, title, tags from bookmarks where id = ?", [id])[0]
    check("update persists", row["url"] == "https://ruby-lang.org/en" && row["title"] == "Ruby home" && row["tags"] == " ruby ", row)
  end

  def test_privacy()
    id = state["id"]
    bob = Client.new(port)
    bob.request("POST", "/signup", {"email": "bob@example.com", "username": "bob", "password": "hunter2hunter2"})
    [_, _, html] = bob.request("GET", "/")
    token = csrf_from(html)
    check("other user sees none of ada's bookmarks", !html.include?("ruby-lang.org") && html.include?("Nothing saved yet"))
    [s, _, _] = bob.request("GET", "/bookmarks/#{id}/edit")
    check("other user's edit form is 404", s == 404, s)
    [s, _, _] = bob.request("POST", "/bookmarks/#{id}", {"csrf_token": token, "url": "https://evil.example", "title": "pwn"})
    check("other user's update is 404", s == 404, s)
    [s, _, _] = bob.request("POST", "/bookmarks/#{id}/delete", {"csrf_token": token})
    check("other user's delete is 404", s == 404, s)
    rows = sql("select count(*) as n from bookmarks where id = ? and url = 'https://ruby-lang.org/en'", [id])
    check("bookmark untouched", rows[0]["n"] == 1, rows)
  end

  def test_delete()
    id = state["id"]
    [s, _, _] = ada.request("POST", "/bookmarks/#{id}/delete", {})
    check("delete without CSRF is 403", s == 403, s)
    [s, _, _] = ada.request("POST", "/bookmarks/#{id}/delete", {"csrf_token": state["token"]})
    check("delete removes it", s == 302 && sql("select count(*) as n from bookmarks")[0]["n"] == 1, s)
  end

  def test_paging()
    now = 1700000000
    db = SQLite3.open(db_path)
    (0...45).each() do |i|
      title = i < 10 ? "Paged 0#{i}" : "Paged #{i}"
      db.execute("insert into bookmarks (user_id, url, title, tags, created_at, updated_at) values (?, ?, ?, ' bulk ', ?, ?)",
        [1, "https://p.example/#{i}", title, now + i, now + i])
    end
    db.close()
    [_, _, html] = ada.request("GET", "/?tag=bulk")
    check("page 1 has 20, newest first", occurrences(html, "class=\"bookmark\"") == 20 && html.include?("Paged 44") && html.include?("Paged 25") && !html.include?("Paged 24") && html.include?("Page 1 of 3"))
    check("pager links keep the filter", html.include?("href=\"/?tag=bulk&amp;page=2\""))
    [_, _, html] = ada.request("GET", "/?tag=bulk&page=3")
    check("last page has the rest", occurrences(html, "class=\"bookmark\"") == 5 && html.include?("Paged 00") && html.include?("Newer") && !html.include?("Older"))
    [_, _, html] = ada.request("GET", "/?tag=bulk&page=99")
    check("page clamps", html.include?("Page 3 of 3"))
  end

  def test_logout_and_login()
    [_, _, html] = ada.request("GET", "/")
    [s, _, _] = ada.request("POST", "/logout", {})
    check("logout without CSRF is 403", s == 403, s)
    [s, _, _] = ada.request("POST", "/logout", {"csrf_token": csrf_from(html)})
    check("logout ends the session", s == 302 && !ada.cookies().has_key?("session_token"), s)
    carol = Client.new(port)
    [s, _, html] = carol.request("POST", "/login", {"email": "ada@example.com", "password": "wrong"})
    check("wrong password is 401", s == 401 && html.include?("Invalid email or password"), s)
    [s, _, _] = carol.request("POST", "/login", {"email": "ada@example.com", "password": "correct horse"})
    check("login works", s == 302 && carol.cookies().has_key?("session_token"), s)
    [_, _, html] = carol.request("GET", "/")
    check("bookmarks are still there after login", html.include?("Paged"))
  end

  suite = Minitest.new()
  suite.test("anonymous visitors", test_anonymous)
  suite.test("signing up", test_signup)
  suite.test("creating bookmarks", test_create)
  suite.test("search and tag filters", test_search)
  suite.test("editing a bookmark", test_edit)
  suite.test("one user cannot touch another's bookmarks", test_privacy)
  suite.test("deleting a bookmark", test_delete)
  suite.test("paging", test_paging)
  suite.test("logging out and back in", test_logout_and_login)
  passed = suite.run()

  server.terminate()
  server.wait()
  if passed
    Process.run(["rm", "-rf", scratch])
  else
    puts("server log: #{log}")
    exit(1)
  end
end

run_tests()

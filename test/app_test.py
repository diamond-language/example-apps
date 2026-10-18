#!/usr/bin/env python3
"""End-to-end test: accounts, sessions, CSRF, bookmark CRUD, tags, search, paging, privacy.
Usage: test/app_test.py [path/to/diamond]"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from support import Server, Checks, csrf_from


def main():
    server = Server(18391)
    check = Checks()
    try:
        # anonymous
        a = server.client()
        s, _, html = a.request("GET", "/")
        check("anonymous home is the welcome page", s == 200 and "Keep the links worth keeping" in html, s)
        s, loc, _ = a.request("GET", "/bookmarks/new")
        check("add form needs sign-in", s == 302 and loc == "/login", (s, loc))
        s, _, _ = a.request("POST", "/bookmarks", {"url": "https://x.example"})
        check("create without a session is refused", s in (302, 403), s)

        # signup
        s, _, html = a.request("POST", "/signup", {"email": "x", "username": "a", "password": "short"})
        check("bad signup is 422 with messages", s == 422 and "email is invalid" in html and "password is too short" in html, (s, html[-600:]))
        s, loc, _ = a.request("POST", "/signup", {"email": "ada@example.com", "username": "ada", "password": "correct horse"})
        check("signup signs in", s == 302 and loc == "/" and "session_token" in a.jar, (s, loc))
        s, _, html = a.request("GET", "/")
        check("home shows flash, empty state and username", "Welcome to Stash" in html and "Nothing saved yet" in html and "@ada" in html)
        token = csrf_from(html)
        check("layout carries a CSRF token", token is not None and len(token) == 64, token)
        s, _, html = a.request("POST", "/signup", {"email": "ada@example.com", "username": "other", "password": "correct horse"})
        check("duplicate email rejected", s == 422 and "email has already been taken" in html)

        # create
        s, _, body = a.request("POST", "/bookmarks", {"url": "https://ruby-lang.org", "title": "Ruby"})
        check("create without CSRF is 403", s == 403 and body == "invalid CSRF token", (s, body))
        s, _, html = a.request("POST", "/bookmarks", {"csrf_token": token, "url": "ftp://nope", "title": "x"})
        check("non-http url rejected", s == 422 and "must start with http" in html, (s, html[-400:]))
        s, _, html = a.request("POST", "/bookmarks", {"csrf_token": token, "url": "", "title": ""})
        check("blank url rejected", s == 422 and "url is required" in html, (s, html[-400:]))
        s, loc, _ = a.request("POST", "/bookmarks", {"csrf_token": token, "url": "https://ruby-lang.org", "title": "Ruby", "note": "the language", "tags": "Ruby, Lang  ruby"})
        check("create redirects home", s == 302 and loc == "/", (s, loc))
        s, loc, _ = a.request("POST", "/bookmarks", {"csrf_token": token, "url": "https://example.com/a?b=1&c=2", "title": "", "tags": "web"})
        rows = server.sql("select title, tags from bookmarks order by id")
        check("tags normalized and deduplicated", rows[0][1] == " ruby lang ", rows)
        check("blank title defaults to the url", rows[1][0] == "https://example.com/a?b=1&c=2", rows)
        s, _, html = a.request("GET", "/")
        check("list shows both, escaped", "Ruby" in html and "the language" in html and "b=1&amp;c=2" in html and "Bookmark saved" in html)
        check("a blank note renders nothing", ">nil<" not in html and html.count('class="note"') == 1, html.count('class="note"'))
        check("tag sidebar counts", 'href="/?tag=ruby"' in html and 'href="/?tag=web"' in html)

        # search and tag filter
        s, _, html = a.request("GET", "/?q=language")
        check("search by note", "ruby-lang.org" in html and "example.com" not in html and "1 result for" in html, html[-900:])
        s, _, html = a.request("GET", "/?tag=web")
        check("filter by tag", "example.com" in html and "ruby-lang.org" not in html and "tagged" in html)
        s, _, html = a.request("GET", "/?tag=ruby&q=nothing-matches")
        check("no match message", "No bookmarks match" in html)
        s, _, html = a.request("GET", "/?q=%3Cscript%3E")
        check("search term is escaped", "<script>" not in html and "&lt;script&gt;" in html)

        # edit / update
        bid = server.sql("select id from bookmarks order by id limit 1")[0][0]
        s, _, html = a.request("GET", "/bookmarks/%d/edit" % bid)
        check("edit form prefilled", s == 200 and 'value="https://ruby-lang.org"' in html and "ruby lang" in html, s)
        s, _, html = a.request("POST", "/bookmarks/%d" % bid, {"csrf_token": token, "url": "https://ruby-lang.org", "title": "", "note": "", "tags": "x"})
        check("update validates (blank title falls back to url, ok)", s == 302, s)
        s, _, html = a.request("POST", "/bookmarks/%d" % bid, {"csrf_token": token, "url": "nope", "title": "t"})
        check("update rejects a bad url", s == 422 and "must start with http" in html)
        s, _, html = a.request("POST", "/bookmarks/%d" % bid, {"csrf_token": token, "url": "https://ruby-lang.org/en", "title": "Ruby home", "note": "n", "tags": "ruby"})
        row = server.sql("select url, title, tags from bookmarks where id=?", (bid,))[0]
        check("update persists", row == ("https://ruby-lang.org/en", "Ruby home", " ruby "), row)

        # privacy
        b = server.client()
        b.request("POST", "/signup", {"email": "bob@example.com", "username": "bob", "password": "hunter2hunter2"})
        s, _, html = b.request("GET", "/")
        btoken = csrf_from(html)
        check("other user sees none of ada's bookmarks", "ruby-lang.org" not in html and "Nothing saved yet" in html)
        s, _, _ = b.request("GET", "/bookmarks/%d/edit" % bid)
        check("other user's edit form is 404", s == 404, s)
        s, _, _ = b.request("POST", "/bookmarks/%d" % bid, {"csrf_token": btoken, "url": "https://evil.example", "title": "pwn"})
        check("other user's update is 404", s == 404, s)
        s, _, _ = b.request("POST", "/bookmarks/%d/delete" % bid, {"csrf_token": btoken})
        check("other user's delete is 404", s == 404, s)
        check("bookmark untouched", server.sql("select count(*) from bookmarks where id=? and url='https://ruby-lang.org/en'", (bid,))[0][0] == 1)

        # delete
        s, loc, _ = a.request("POST", "/bookmarks/%d/delete" % bid, {})
        check("delete without CSRF is 403", s == 403, s)
        s, loc, _ = a.request("POST", "/bookmarks/%d/delete" % bid, {"csrf_token": token})
        check("delete removes it", s == 302 and server.sql("select count(*) from bookmarks")[0][0] == 1, (s,))

        # paging
        now = 1700000000
        rows = [(1, "https://p.example/%d" % i, "Paged %02d" % i, now + i) for i in range(45)]
        for r in rows:
            server.sql("insert into bookmarks (user_id, url, title, tags, created_at, updated_at) values (?, ?, ?, ' bulk ', ?, ?)", (r[0], r[1], r[2], r[3], r[3]))
        s, _, html = a.request("GET", "/?tag=bulk")
        check("page 1 has 20, newest first", html.count('class="bookmark"') == 20 and "Paged 44" in html and "Paged 25" in html and "Paged 24" not in html and "Page 1 of 3" in html, html.count('class="bookmark"'))
        s, _, html = a.request("GET", "/?tag=bulk&page=3")
        check("last page has the rest", html.count('class="bookmark"') == 5 and "Paged 00" in html and "Newer" in html and "Older" not in html)
        s, _, html = a.request("GET", "/?tag=bulk&page=99")
        check("page clamps", "Page 3 of 3" in html)
        check("pager links keep the filter", 'href="/?tag=bulk&amp;page=2"' in a.request("GET", "/?tag=bulk")[2])

        # logout and login
        s, _, html = a.request("GET", "/")
        s, loc, _ = a.request("POST", "/logout", {})
        check("logout without CSRF is 403", s == 403)
        s, loc, _ = a.request("POST", "/logout", {"csrf_token": csrf_from(html)})
        check("logout ends the session", s == 302 and "session_token" not in a.jar, (s, a.jar))
        c = server.client()
        s, _, html = c.request("POST", "/login", {"email": "ada@example.com", "password": "wrong"})
        check("wrong password 401", s == 401 and "Invalid email or password" in html)
        s, loc, _ = c.request("POST", "/login", {"email": "ada@example.com", "password": "correct horse"})
        check("login works", s == 302 and "session_token" in c.jar)
        s, _, html = c.request("GET", "/")
        check("bookmarks are still there after login", "Paged" in html)
    finally:
        server.stop()
    check.finish(server)


main()

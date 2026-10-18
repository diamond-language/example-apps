# HTTP <-> operations: handlers read params, call Accounts / Bookmarks, and pick a response.
class AccountPages
  def self.signup_form(conn) = Pages.render(conn, "Sign up", signup_html([], "", ""))

  def self.signup(conn)
    result = Accounts.signup(conn.repo(), conn.schemas(), conn.params())
    case result
    when Mjolnir::Ok
      Auth.sign_in(conn, result.value())
      Auth.flash_redirect(conn, "/", "Welcome to Stash")
    when Mjolnir::Err
      Pages.render(conn, "Sign up", signup_html(result.error(), conn.params()["email"], conn.params()["username"]), status: 422)
    end
  end

  def self.login_form(conn) = Pages.render(conn, "Sign in", login_html(nil))

  def self.login(conn)
    user = Accounts.authenticate(conn.repo(), conn.schemas(), conn.params()["email"], conn.params()["password"])
    if user == nil
      return Pages.render(conn, "Sign in", login_html("Invalid email or password"), status: 401)
    end
    Auth.sign_in(conn, user)
    Auth.flash_redirect(conn, "/", "Signed in")
  end

  def self.logout(conn)
    Auth.sign_out(conn)
    Auth.flash_redirect(conn, "/login", "Signed out")
  end
end

class BookmarkPages
  def self.index(conn)
    if conn.user() == nil then return Pages.render(conn, "Stash", welcome_html()) end
    page = Bookmarks.list(conn.repo(), conn.schemas(), conn.user(), conn.params())
    tags = Bookmarks.tag_counts(conn.repo(), conn.schemas(), conn.user())
    Pages.render(conn, "Your bookmarks", index_html(page, tags, conn.csrf_token()))
  end

  def self.new_form(conn)
    url = conn.params()["url"]
    title = conn.params()["title"]
    prefill = {"url": if url == nil then "" else url end, "title": if title == nil then "" else title end, "note": "", "tags": ""}
    Pages.render(conn, "Add a bookmark", bookmark_form_html("/bookmarks", prefill, [], conn.csrf_token(), "Add"))
  end

  def self.create(conn)
    result = Bookmarks.create(conn.repo(), conn.schemas(), conn.user(), conn.params())
    case result
    when Mjolnir::Ok
      Auth.flash_redirect(conn, "/", "Bookmark saved")
    when Mjolnir::Err
      Pages.render(conn, "Add a bookmark", bookmark_form_html("/bookmarks", conn.params(), result.error(), conn.csrf_token(), "Add"), status: 422)
    end
  end

  def self.edit_form(conn)
    bookmark = Bookmarks.find(conn.repo(), conn.schemas(), conn.user(), conn.route_params()["id"])
    if bookmark == nil then return Web.not_found(conn.path()) end
    values = {"url": bookmark.url(), "title": bookmark.title(), "note": if bookmark.note() == nil then "" else bookmark.note() end, "tags": Bookmarks.tag_list(bookmark.tags()).join(" ")}
    Pages.render(conn, "Edit bookmark", bookmark_form_html("/bookmarks/#{bookmark.id()}", values, [], conn.csrf_token(), "Save"))
  end

  def self.update(conn)
    bookmark = Bookmarks.find(conn.repo(), conn.schemas(), conn.user(), conn.route_params()["id"])
    if bookmark == nil then return Web.not_found(conn.path()) end
    result = Bookmarks.update(conn.repo(), conn.schemas(), bookmark, conn.params())
    case result
    when Mjolnir::Ok
      Auth.flash_redirect(conn, "/", "Bookmark updated")
    when Mjolnir::Err
      Pages.render(conn, "Edit bookmark", bookmark_form_html("/bookmarks/#{bookmark.id()}", conn.params(), result.error(), conn.csrf_token(), "Save"), status: 422)
    end
  end

  def self.destroy(conn)
    bookmark = Bookmarks.find(conn.repo(), conn.schemas(), conn.user(), conn.route_params()["id"])
    if bookmark == nil then return Web.not_found(conn.path()) end
    Bookmarks.delete(conn.repo(), conn.schemas(), bookmark)
    Auth.flash_redirect(conn, "/", "Bookmark deleted")
  end
end

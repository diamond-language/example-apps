# Database-backed sessions in a signed cookie, a signed one-shot flash cookie,
# and per-session CSRF tokens. A request is loaded before its route's guards
# run (Auth.load) and its response is finished after them (Auth.finish), which
# is where cookies queued on the conn (session start/end, flash) are emitted.
def session_cookie_name() = "session_token"
def flash_cookie_name() = "flash"
def session_seconds() = 30 * 24 * 60 * 60

class Auth
  def self.secret()
    secret = ENV["STASH_SESSION_SECRET"]
    if secret == nil then "dev-only-insecure-secret-change-me" else secret end
  end

  def self.session_cookie(value, max_age) = cookie_serialize(session_cookie_name(), value, {"path": "/", "http_only": true, "same_site": "Lax", "max_age": max_age})
  def self.flash_cookie(value, max_age) = cookie_serialize(flash_cookie_name(), value, {"path": "/", "http_only": true, "same_site": "Lax", "max_age": max_age})

  # Fills conn.user / session / csrf_token from the session cookie, and
  # conn.flash_in from the flash cookie. A cookie that fails its signature
  # never reaches the database; a stale or expired session is cleared.
  def self.load(conn)
    header = conn.header("cookie")
    if header == nil then return end
    cookies = cookie_parse(header)
    raw_flash = cookies[flash_cookie_name()]
    if raw_flash != nil
      verified = SignedCookies.verify(raw_flash, Auth.secret())
      if verified != nil
        parsed = JSON.parse(verified)
        if parsed.is_a?(Hash) then conn.flash_in = parsed end
      end
      # one request only, whether or not it verified
      conn.cookies_out().push(Auth.flash_cookie("", 0))
    end
    raw = cookies[session_cookie_name()]
    if raw == nil then return end
    token = SignedCookies.verify(raw, Auth.secret())
    if token == nil then return end
    repo = conn.repo()
    sessions = conn.schemas().sessions()
    session = repo.get_by(sessions, {"token": token})
    if session == nil
      conn.cookies_out().push(Auth.session_cookie("", 0))
      return
    end
    if session.expires_at() <= Time.now().to_i()
      repo.delete(sessions, session.id())
      conn.cookies_out().push(Auth.session_cookie("", 0))
      return
    end
    user = repo.get(conn.schemas().users(), session.user_id())
    if user != nil
      conn.user = user
      conn.session = session
      conn.csrf_token = session.csrf_token()
    end
  end

  # Creates a session row and queues its signed cookie; the caller redirects.
  def self.sign_in(conn, user)
    token = SecureRandom.hex(32)
    csrf_token = SecureRandom.hex(32)
    changeset = Mjolnir::Changeset.cast(conn.schemas().sessions(), nil,
      {"user_id": user.id(), "token": token, "csrf_token": csrf_token, "expires_at": Time.now().to_i() + session_seconds()},
      ["user_id", "token", "csrf_token", "expires_at"])
    conn.repo().insert!(changeset)
    conn.cookies_out().push(Auth.session_cookie(SignedCookies.sign(token, Auth.secret()), session_seconds()))
  end

  def self.sign_out(conn)
    if conn.session() != nil
      conn.repo().delete(conn.schemas().sessions(), conn.session().id())
    end
    conn.cookies_out().push(Auth.session_cookie("", 0))
  end

  # Redirect that shows `message` on the page it lands on.
  def self.flash_redirect(conn, location, message, kind: String = "notice")
    out = conn.flash_out()
    out[kind] = message
    Web.redirect(location)
  end

  # Emits the cookies queued during the request. A flash set by this request
  # replaces the clearing cookie for the one consumed by it.
  def self.finish(conn, response)
    cookies = conn.cookies_out()
    flash = conn.flash_out()
    if flash.length() > 0
      cookies = cookies.select() do |c| !c.start_with?(flash_cookie_name() + "=") end
      cookies.push(Auth.flash_cookie(SignedCookies.sign(JSON.stringify(flash), Auth.secret()), 60))
    end
    if cookies.length() == 0 then return response end
    headers = response[1]
    headers["Set-Cookie"] = cookies
    response
  end
end

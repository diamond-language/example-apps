# Route guards: (conn) -> nil to continue, or a response that stops the request.
def require_authentication(conn)
  if conn.user() == nil
    return Auth.flash_redirect(conn, "/login", "Please sign in to continue", kind: "alert")
  end
  nil
end

def require_csrf(conn)
  expected = conn.csrf_token()
  supplied = conn.params()["csrf_token"]
  if expected == nil || supplied == nil || !constant_time_equal(expected, supplied)
    return Web.text(403, "invalid CSRF token")
  end
  nil
end

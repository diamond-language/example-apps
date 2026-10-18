# Wraps a page body in the layout for this request's user, CSRF token and flash.
class Pages
  def self.render(conn, title, content, status: Int = 200)
    [status, {"Content-Type": "text/html; charset=utf-8"}, layout_html(title, content, conn.user(), conn.csrf_token(), conn.flash_in())]
  end
end

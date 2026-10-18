# A small request pipeline. A Conn carries one request through ordered steps;
# a step is a function (conn) -> nil to continue or a response to stop. The
# router picks the handler, whose route-level guards run first.
module Web
  class Conn
    attr_reader request, method, path, params
    attr_accessor user, session, csrf_token, route_params, repo, schemas, flash_in, flash_out, cookies_out, assigns

    def initialize(request)
      @request = request
      @method = request["method"]
      target = request["path"]
      q = target.index_of("?")
      @path = if q == nil then target else target.slice(0, q) end
      @params = {}
      if q != nil
        Web.parse_pairs(target.slice(q + 1, target.length()), @params)
      end
      content_type = request["headers"]["content-type"]
      if @method == "POST" && request["body"] != nil && (content_type == nil || content_type.start_with?("application/x-www-form-urlencoded"))
        Web.parse_pairs(request["body"], @params)
      end
      @route_params = {}
      @user = nil
      @session = nil
      @csrf_token = nil
      @repo = nil
      @schemas = nil
      @flash_in = {}
      @flash_out = {}
      @cookies_out = []
      @assigns = {}
    end

    def header(name) = @request["headers"][name]
  end

  # "a=1&b=2" -> into `out` (decoded).
  def self.parse_pairs(text, out)
    text.split("&").each() do |pair|
      eq = pair.index_of("=")
      if eq != nil
        out[url_decode(pair.slice(0, eq))] = url_decode(pair.slice(eq + 1, pair.length()))
      end
    end
    out
  end

  def self.html(body: String) = [200, {"Content-Type": "text/html; charset=utf-8"}, body]
  def self.text(status: Int, body: String) = [status, {"Content-Type": "text/plain; charset=utf-8"}, body]
  def self.redirect(location: String) = [302, {"Location": location}, ""]
  def self.status_text(status: Int, body: String) = Web.text(status, body)
  def self.not_found(path: String) = Web.text(404, "not found: #{path}")

  # Routes: exact paths in a Hash, patterns with ":name" captures in a list,
  # each entry [method, segments, guards, handler].
  class Router
    def initialize()
      @exact = {}
      @patterns = []
    end

    def get(path, handler, guards = []) -> Router = self.add("GET", path, handler, guards)
    def post(path, handler, guards = []) -> Router = self.add("POST", path, handler, guards)

    def add(method, path, handler, guards) -> Router
      route = [method, path.split("/"), guards, handler]
      if path.index_of(":") == nil
        @exact["#{method} #{path}"] = route
      else
        @patterns.push(route)
      end
      self
    end

    # [guards, handler] for the request, with captures stored on the conn, or nil.
    def match(conn)
      key = "#{conn.method()} #{conn.path()}"
      found = @exact[key]
      if found != nil
        return [found[2], found[3]]
      end
      parts = conn.path().split("/")
      @patterns.each() do |route|
        if route[0] == conn.method()
          captures = Router.capture(route[1], parts)
          if captures != nil
            conn.route_params = captures
            return [route[2], route[3]]
          end
        end
      end
      nil
    end

    def self.capture(pattern, parts)
      if pattern.length() != parts.length()
        return nil
      end
      captures = {}
      i = 0
      while i < pattern.length()
        segment = pattern[i]
        if segment.start_with?(":")
          captures[segment.slice(1, segment.length())] = url_decode(parts[i])
        elsif segment != parts[i]
          return nil
        end
        i += 1
      end
      captures
    end

    # Runs the guards, then the handler; the first non-nil guard result is the response.
    def dispatch(conn)
      matched = self.match(conn)
      if matched == nil
        return Web.not_found(conn.path())
      end
      matched[0].each() do |guard|
        halted = guard(conn)
        if halted != nil
          return halted
        end
      end
      matched[1](conn)
    end
  end
end

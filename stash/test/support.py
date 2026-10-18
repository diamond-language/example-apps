"""Shared helpers for the HTTP tests: a cookie-aware client and a throwaway server."""
import http.client, os, re, signal, sqlite3, subprocess, sys, tempfile, time, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__)) + "/.."
DIAMOND = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("DIAMOND_BIN", "diamond")


class Client:
    def __init__(self, port):
        self.port = port
        self.jar = {}

    def request(self, method, path, form=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=60)
        headers = {}
        if self.jar:
            headers["Cookie"] = "; ".join("%s=%s" % kv for kv in self.jar.items())
        body = None
        if form is not None:
            body = urllib.parse.urlencode(form)
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        conn.request(method, path, body, headers)
        resp = conn.getresponse()
        text = resp.read().decode("utf-8", "replace")
        for header, value in resp.getheaders():
            if header.lower() == "set-cookie":
                name, _, rest = value.split(";")[0].partition("=")
                if "Max-Age=0" in value:
                    self.jar.pop(name, None)
                else:
                    self.jar[name] = rest
        conn.close()
        return resp.status, resp.getheader("Location"), text


def csrf_from(html):
    m = re.search(r'name="csrf_token" value="([0-9a-f]+)"', html)
    return m.group(1) if m else None


class Server:
    """Stash on a fresh database built from db/schema.sql."""
    def __init__(self, port):
        self.port = port
        self.work = tempfile.mkdtemp(prefix="stash-test-")
        self.db = self.work + "/t.db"
        con = sqlite3.connect(self.db)
        con.executescript(open(HERE + "/db/schema.sql").read())
        con.commit(); con.close()
        env = dict(os.environ, STASH_DB=self.db, PORT=str(port), STASH_SESSION_SECRET="test-secret-test-secret-test-secret")
        self.proc = subprocess.Popen([DIAMOND, "app.di"], cwd=HERE, env=env, stdout=open(self.work + "/log", "w"), stderr=subprocess.STDOUT)
        for _ in range(300):
            try:
                self.client().request("GET", "/css/app.css"); return
            except OSError:
                time.sleep(0.1)
        raise SystemExit("server never came up; see " + self.work + "/log")

    def client(self):
        return Client(self.port)

    def sql(self, query, args=()):
        con = sqlite3.connect(self.db)
        try:
            rows = con.execute(query, args).fetchall(); con.commit(); return rows
        finally:
            con.close()

    def stop(self):
        self.proc.send_signal(signal.SIGTERM); self.proc.wait(timeout=10)


class Checks:
    def __init__(self):
        self.failures = []

    def __call__(self, name, ok, detail=""):
        print(("ok   " if ok else "FAIL ") + name + ("" if ok else "  " + str(detail)))
        if not ok:
            self.failures.append(name)

    def finish(self, server):
        if self.failures:
            print("\n%d failure(s); server log: %s/log" % (len(self.failures), server.work)); sys.exit(1)
        print("\nall passed")

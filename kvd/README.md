# kvd

A small key-value server and its client, written in [Diamond](https://getdiamond.codes).
It started as `facet new tcp kvd`. One thread serves every client with `IO.poll`.

```sh
facet install                                # fetch minitest, the test library, into cuts/
DATA=kvd.json diamond main.d6                # listens on 127.0.0.1:7000
diamond client.d6 SET greeting hello there   # OK
diamond client.d6 GET greeting               # hello there
printf 'INCR hits\nKEYS\n' | diamond client.d6
bash test.sh                                 # run the tests
diamond build main.d6 -o kvd                 # standalone executables
diamond build client.d6 -o kvd-client
```

`PORT` and `HOST` set the address for both programs. The default host, `127.0.0.1`, is
reachable only from this machine; `HOST=0.0.0.0` accepts outside connections, and kvd has
no authentication, so only do that on a network you trust. `DATA` names a JSON file that
holds the keys; every change is written through to it, so a restarted server picks up where
it left off. Without `DATA` the keys live in memory.

## Protocol

One request per line: a command and its arguments separated by spaces. Commands ignore
case. `SET`'s value is the rest of the line, spaces included. Each reply starts with a type
character, so `nc 127.0.0.1 7000` is a usable client too.

| Request | Reply |
|---|---|
| `PING` | `+PONG` |
| `SET key value...` | `+OK` |
| `GET key` | `$value`, or `_` if there is no such key |
| `DEL key` | `:1` if it existed, else `:0` |
| `INCR key [by]` | `:total`; a missing key counts as 0 |
| `KEYS [prefix]` | `*n`, then n lines of `$key`, sorted |
| `QUIT` | `+BYE`, then the server closes the connection |

A bad request gets `-ERR reason` and the connection stays open. A line longer than 64 KiB
closes the connection, so a client can't make the server buffer without limit.

The client prints values bare, `_` as `(nil)` and errors on stderr. It exits 1 if any reply
was an error and 69 (`EX_UNAVAILABLE`) if it can't reach the server.

## Files

- `main.d6` starts the server; `INT` and `TERM` stop it.
- `lib/kvd.d6` holds `Store` (the data and its file) and `Kvd` (the protocol and the
  `IO.poll` server loop).
- `client.d6` and `lib/client.d6` are the client.
- `test/kvd_test.d6` tests the protocol and the store, then starts the real server on a
  free port and talks to it with the client.

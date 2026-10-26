# Diamond example apps

Small, complete applications written in [Diamond](https://github.com/diamond-language/diamond), each in its
own directory with its own README, cuts (`diamond.cut`, installed with `facet install`) and tests.

| App | What it shows |
|---|---|
| [`stash`](stash) | A private bookmark manager: Gremlin (server), Div (views), Mjolnir (data), accounts and sessions, CSRF, tags, search, paging |
| [`tasks`](tasks) | A to-do list for the terminal: subcommands, exit statuses, a JSON file saved atomically, XDG paths |
| [`kvd`](kvd) | A key-value server and client over a line protocol: one-thread `IO.poll` serving, write-through persistence, signal handling |

Skindicate, Diamond's production app, lives in its own repository and is not an example.

## Running an app

Install Diamond (and `facet`) from the main repository, then in an app's directory:

```sh
facet install
./compile_views.sh   # if the app has Div views
diamond app.di       # or main.d6, as the app's README says
```

Each app's README lists its own settings and how to run its tests.

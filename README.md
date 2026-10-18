# Diamond example apps

Small, complete applications written in [Diamond](https://github.com/diamond-language/diamond), each in its
own directory with its own README, cuts (`diamond.cut`, installed with `facet install`) and tests.

| App | What it shows |
|---|---|
| [`stash`](stash) | A private bookmark manager: Gremlin (server), Div (views), Mjolnir (data), accounts and sessions, CSRF, tags, search, paging |

Skindicate, Diamond's production app, lives in its own repository and is not an example.

## Running an app

Install Diamond (and `facet`) from the main repository, then in an app's directory:

```sh
facet install
./compile_views.sh   # if the app has Div views
diamond app.di
```

Each app's README lists its own settings and how to run its tests.

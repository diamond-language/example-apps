# Stash

A private bookmark shelf written in Diamond: save a link, tag it, search it.
Built on Gremlin (server), Div (views) and Mjolnir (data), with the same shape as
`../SkindicateV3`: a `Conn` flows through guards to a handler; operations return
`Ok`/`Err`; views are pure functions of data.

## Features

- Accounts (email, username, password of at least 8 characters), database-backed sessions in signed cookies, CSRF tokens on every write.
- Bookmarks: add, edit, delete. A blank title defaults to the URL; only `http(s)` URLs are accepted.
- Tags (space or comma separated, lowercased, deduplicated, at most ten), a tag sidebar with counts, and a filter per tag.
- Search across title, URL, note and tags; 20 per page, newest first.
- Private by design: every lookup is scoped to the signed-in user, so another user's bookmark is a 404.

## Run

```sh
tools/setup_cuts.sh                        # install the local cuts Stash loads
./compile_views.sh                         # re-run after editing anything in views/
../diamond/build/diamond app.di            # prints its address; creates data/stash.db on first run
```

`STASH_DB` (default `data/stash.db`), `PORT` (default 18300), `STASH_THREADS` (default 1) and
`STASH_SESSION_SECRET` (set a long random string in production) configure it.

## Test

`python3 test/app_test.py [path/to/diamond]` starts a throwaway server and checks signup, login,
CSRF, CRUD, tags, search, paging and that one user cannot touch another's bookmarks.

## Notes

- Tags live in one column as `" a b c "` (a space each side), so a tag filter is `LIKE '% tag %'`.
  That is exact and simple at personal scale; a join table is the move if tags need renaming or stats.
- A multi-worker server (`STASH_THREADS`) runs no top-level statements in a worker, so shared values are
  functions (`lib/util.di`), as in SkindicateV3.

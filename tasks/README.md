# tasks

A to-do list for the terminal, written in [Diamond](https://getdiamond.codes). It
started as `facet new cli tasks`.

```sh
facet install                      # fetch minitest, the test library, into cuts/
diamond main.d6 add buy milk       # added 1: buy milk
diamond main.d6 add call mom       # added 2: call mom
diamond main.d6 done 1             # done 1: buy milk
diamond main.d6                    # 2 [ ] call mom  (2026-10-26)
diamond main.d6 list --all         # finished tasks too
diamond main.d6 --help             # every command
bash test.sh                       # run the tests
diamond build main.d6 -o tasks     # a standalone executable
```

The list is a JSON file: `--file PATH`, else `$TASKS_FILE`, else
`$XDG_DATA_HOME/tasks/tasks.json`, which defaults to `~/.local/share/tasks/tasks.json`. A
save writes a temporary file and renames it over the old one, so an interrupted save never
leaves half a list.

Exit status: 0 on success, 64 (`EX_USAGE`) when the command was called wrong, 1 for
anything else, such as an id that doesn't exist. Ids are never reused, so `done 3` can't
finish a different task than the one once listed as 3, and a command given several ids
changes nothing unless every id exists.

- `main.d6` passes `ARGV` to `Tasks.main` and exits with the status it returns.
- `lib/tasks.d6` holds the commands. Each returns the lines to print, so the tests check
  them without capturing output.
- `test/tasks_test.d6` tests the commands and, through `Tasks.main`, the saved file and
  the exit statuses.

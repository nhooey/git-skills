# git-workflow-tidy-branches defaults

`tidy-branches.py` reads this file on every start, then the user's and the
project's `git-workflow-tidy-branches.preferences.md` over it, a later file
winning key by key. A preferences file names only the keys it changes; a
list there replaces the list here whole. An unknown key is an error.

- Base:
  The branch the others are compared with, as a ref like `upstream/main`.
  Empty: the default branch of a remote named `upstream`, else that of the
  push remote, else a local `main` or `master`. Write `Base:` with no
  value to clear a base an earlier file set.
- Push remote: origin
  The remote whose branches are deleted and pushed to.
- Keep:
  Branch globs that are never deleted or rebased. The base's own name is
  always kept as well.
  - main
  - master
  - release/*
- Delete merged: ask
  Branches already in the base: `ask` puts them to the user, `yes`
  deletes them without asking, `no` leaves them out of the plan.
- Rebase: ask
  Branches behind the base that replay onto it without a conflict: `ask`,
  `yes` or `no`, as for `Delete merged`.
- Rebase open pull requests: ask
  Overrides `Rebase` for branches with an open pull request, since every
  force-push notifies the reviewer and resets "changes since your last
  review": `ask`, `yes` or `no`.

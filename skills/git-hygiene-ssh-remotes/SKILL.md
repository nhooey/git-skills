---
name: git-hygiene-ssh-remotes
description: |
  Use SSH remotes (`git@github.com:owner/repo.git`) over HTTPS. SSH
  avoids per-push username and token prompts when `ssh-agent` is loaded;
  HTTPS needs a credential helper or repeats the prompts. Use when adding
  a remote, cloning a repo, or hitting credential prompts.
tags: [setup, style]
allowed-tools:
  - Bash
  - Read
---

# SSH remotes

_Add and clone remotes in their SSH form, and use HTTPS only for one of the reasons below._

When adding a remote (or cloning), prefer the SSH form:

```
git@github.com:<owner>/<repo>.git
```

over the HTTPS form:

```
https://github.com/<owner>/<repo>.git
```

## Why

HTTPS prompts for a username and a personal access token on every push,
and on every fetch from a private repo, unless a credential helper is
configured (macOS Keychain, `git-credential-manager`, `gh auth setup-git`).
SSH uses the key already loaded in your `ssh-agent`: no prompt, no token
to rotate, no helper to configure per machine.

## Switch an existing remote

```bash
git remote set-url origin git@github.com:<owner>/<repo>.git
git remote -v   # verify
```

## For tools that default to HTTPS

`gh repo clone` and `gh repo create --source=. --push` follow gh's
`git_protocol` setting, which defaults to `https`. Pass `gh repo clone`
the SSH URL itself, or fix the remote afterward with `set-url`.
`gh config set git_protocol ssh` changes it for every repo, so ask the
user before running it.

## Good reasons to use HTTPS instead

- A network or firewall blocks port 22 (corporate proxies sometimes
  do). GitHub offers SSH over port 443 at `ssh.github.com:443`; try that
  before falling back to HTTPS.
- The host doesn't support SSH at all (rare for major forges).
- A short-lived ephemeral environment (CI runner, Codespace) where
  setting up a deploy key is more friction than a token. Even then,
  prefer short-lived OIDC tokens or `gh auth` over a long-lived PAT.

When you do use HTTPS for a real reason, a credential helper saves
re-typing tokens: `gh auth setup-git`, or
`git config --global credential.helper osxkeychain` on macOS. Both
change git's configuration for every repo, so ask the user first.

## When to apply

- Adding a new remote.
- Cloning a repo.
- Hitting a credential prompt that wasn't expected.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `shell-hygiene-no-machine-wide-changes`: asking before `git config --global`, `gh config set` and other changes beyond the project.

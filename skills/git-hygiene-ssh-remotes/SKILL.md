---
name: git-hygiene-ssh-remotes
description: |
  Use SSH remotes (`git@github.com:owner/repo.git`) over HTTPS. SSH
  avoids per-push username/PAT prompts when `ssh-agent` is loaded; HTTPS
  needs a credential helper or repeats prompts. Apply when adding a
  remote, cloning a repo, or hitting credential prompts.
tags: [setup, style]
allowed-tools:
  - Bash
  - Read
---

# git-hygiene-ssh-remotes

When adding a remote (or cloning), prefer the SSH form:

```
git@github.com:<owner>/<repo>.git
```

over the HTTPS form:

```
https://github.com/<owner>/<repo>.git
```

## How to load this skill

Passive reference. Loading it doesn't mean you should reconfigure
remotes now — just that when you add or clone a remote, you'll pick
SSH.

## Why

HTTPS prompts for a username and a Personal Access Token on every push
and fetch, unless you've installed and configured a credential helper
(macOS Keychain, `git-credential-manager`, etc.). SSH uses the key
already loaded in your `ssh-agent` — no prompt, no token to rotate, no
helper to configure per machine. If your other repos "just work"
without prompting, they almost certainly use SSH.

## Switch an existing remote

```bash
git remote set-url origin git@github.com:<owner>/<repo>.git
git remote -v   # verify
```

## For tools that default to HTTPS

E.g. `gh repo clone`, `gh repo create --source=. --push` — either pass
`--ssh` / configure `gh config set git_protocol ssh`, or fix the remote
afterward with `set-url`.

## Good reasons to use HTTPS instead (the "unless" cases)

- A network or firewall blocks port 22 (corporate proxies sometimes
  do). GitHub offers SSH-over-443 at `ssh.github.com:443` as a
  workaround before falling back to HTTPS — try that first.
- The host doesn't support SSH at all (rare for major forges).
- A short-lived ephemeral environment (CI runner, Codespace) where
  setting up a deploy key is more friction than a token. Even then,
  prefer short-lived OIDC tokens or `gh auth` over a long-lived PAT.

When you do use HTTPS for a real reason, set up a credential helper so
you're not re-typing tokens. On macOS:
`git config --global credential.helper osxkeychain`.

The default should be SSH; the burden of justification is on HTTPS.

## When to apply

- Adding a new remote.
- Cloning a repo.
- Hitting a credential prompt that wasn't expected.

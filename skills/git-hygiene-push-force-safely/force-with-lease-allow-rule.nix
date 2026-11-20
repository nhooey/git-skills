# Claude Code settings that let an agent force-push with a lease without a
# permission prompt, for a Home Manager configuration to merge into the
# user's settings, as is:
#
#   programs.claude-code.settings = lib.recursiveUpdate otherSettings
#     (import "${git-skills}/skills/git-hygiene-push-force-safely/force-with-lease-allow-rule.nix");
#
# The rule matches a push to any branch, the default branch among them.
# It relies on a server-side block of default-branch rewrites where
# GitHub allows one (a ruleset blocking force pushes and deletion of the
# default branch), and on two hooks everywhere else, such as private
# repositories on GitHub Free and forks. Don't install it without both:
#
# - the git pre-push hook, the flake package
#   `git-hooks-default-branch-guard`, as the global `core.hooksPath`;
# - the Claude Code PreToolUse hook `push-hook-bypass-guard.sh` in the
#   `git-skills-hooks` plugin, the flake package `hooks-plugin`, which
#   denies a push that skips the pre-push hook.
{
  permissions.allow = [ "Bash(git push --force-with-lease=*)" ];
}

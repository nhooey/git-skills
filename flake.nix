{
  description = "skills-git: Claude Code skills marketplace as a Nix flake (git hygiene, GitHub repo settings, agent PR lifecycle)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills.url = "github:nhooey/flake-skills/configurable-package-prefix";
    flake-skills.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, flake-skills, ... }@inputs:
    let
      base = flake-skills.lib.mkAllSkillsFlake {
        inherit nixpkgs;
        skillsDir = ./skills;
        packagePrefix = "agent-skill-";
      };

      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forSystems = nixpkgs.lib.genAttrs systems;

      packs = {
        # All 11 git-* skills.
        git-pack-all = [
          "git-branch-naming"
          "git-clean-local-history"
          "git-cleanup-merged-branches"
          "git-commit-message-format"
          "git-conventional-commits"
          "git-push-force-safely"
          "git-gitignore-discipline"
          "git-inspect-before-commit"
          "git-no-history-in-code"
          "git-push-workflow-mode"
          "git-ssh-remotes"
        ];

        # Narrow subset: universally-good git rules with broad team appeal.
        # Excludes opinionated style (branch-naming, CC) and interactive
        # workflow (push-workflow-mode, cleanup-merged-branches).
        git-pack-minimal = [
          "git-commit-message-format"
          "git-push-force-safely"
          "git-gitignore-discipline"
          "git-ssh-remotes"
        ];

        # All 9 github-* skills (includes the agent-* trio).
        github-pack-all = [
          "github-changeset-prompt"
          "github-pr-status-line"
          "github-pr-watcher"
          "github-auto-delete-merged-branches"
          "github-codeowners"
          "github-gh-cli-gotchas"
          "github-merge-commits-only"
          "github-pr-mirrors-commit"
          "github-protect-default-branch"
        ];

        # One-time repo configuration: branch protection, auto-delete, owners.
        github-pack-setup = [
          "github-auto-delete-merged-branches"
          "github-codeowners"
          "github-protect-default-branch"
        ];

        # The three purely agent-flavored skills (pr-watcher, pr-status-line,
        # changeset-prompt). Only meaningful when an LLM is driving.
        agent-pack = [
          "github-changeset-prompt"
          "github-pr-status-line"
          "github-pr-watcher"
        ];
      };

      mkPack =
        system: skillNames:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.symlinkJoin {
          name = "skills-pack";
          paths = builtins.map (n: base.packages.${system}."agent-skill-${n}") skillNames;
        };

      packPackages = forSystems (
        system: nixpkgs.lib.mapAttrs (_: skills: mkPack system skills) packs
      );
    in
    base
    // {
      packages = nixpkgs.lib.recursiveUpdate base.packages packPackages;
    };
}

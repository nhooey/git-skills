{
  description = "skills-git: Claude Code skills marketplace as a Nix flake (git hygiene, GitHub repo settings, agent PR lifecycle)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills.url = "github:nhooey/flake-skills";
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
        agent-skills-git-all = [
          "git-hygiene-branch-naming"
          "git-hygiene-local-history"
          "git-hygiene-cleanup-merged-branches"
          "git-hygiene-commit-message-format"
          "git-hygiene-conventional-commits"
          "git-hygiene-push-force-safely"
          "git-hygiene-gitignore"
          "git-hygiene-inspect-before-commit"
          "git-hygiene-no-history-in-code"
          "git-push-workflow-mode"
          "git-ssh-remotes"
        ];

        # Narrow subset: universally-good git rules with broad team appeal.
        # Excludes opinionated style (branch-naming, CC) and interactive
        # workflow (push-workflow-mode, merged-branches).
        agent-skills-git-minimal = [
          "git-hygiene-commit-message-format"
          "git-hygiene-push-force-safely"
          "git-hygiene-gitignore"
          "git-ssh-remotes"
        ];

        # All github-* skills (includes the agent-* trio).
        agent-skills-github-all = [
          "github-changeset-prompt"
          "github-pull-request-status-line"
          "github-pull-request-watcher"
          "github-gh-cli-gotchas"
          "github-hygiene-pull-request-mirrors-commit"
          "github-policy-auto-delete-merged-branches"
          "github-policy-codeowners"
          "github-policy-merge-commits-only"
          "github-policy-protect-default-branch"
          "github-stacked-pull-requests"
        ];

        # One-time repo configuration: branch protection, auto-delete, owners.
        agent-skills-github-setup = [
          "github-policy-auto-delete-merged-branches"
          "github-policy-codeowners"
          "github-policy-protect-default-branch"
        ];

        # The three purely agent-flavored skills covering the changeset
        # → PR open → watch loop. Only meaningful when an LLM is driving.
        agent-skills-github-pull-request-lifecycle = [
          "github-changeset-prompt"
          "github-pull-request-status-line"
          "github-pull-request-watcher"
        ];
      };

      # Build a `flake-skills.lib.mkSkillsEnv` for one (packName,
      # skillNames) pair. The env keeps the same `nix run`/`nix build`
      # UX as a plain `symlinkJoin`, but also carries the
      # `passthru.isFlakeSkillsEnv` + `flakeSkillsEnv` records that
      # `programs.flake-skills.skills` needs to expand the env back
      # into per-skill records on home-manager activation.
      mkEnv =
        system: packName: skillNames:
        flake-skills.lib.mkSkillsEnv {
          pkgs = nixpkgs.legacyPackages.${system};
          name = packName;
          skills = builtins.map (n: base.packages.${system}."agent-skill-${n}") skillNames;
        };

      packPackages = forSystems (
        system: nixpkgs.lib.mapAttrs (packName: skills: mkEnv system packName skills) packs
      );
    in
    base
    // {
      packages = nixpkgs.lib.recursiveUpdate base.packages packPackages;
    };
}

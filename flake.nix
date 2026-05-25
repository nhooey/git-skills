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
          "git-hygiene-commit-message-format"
          "git-hygiene-conventional-commits"
          "git-hygiene-gitignore"
          "git-hygiene-no-history-in-code"
          "git-hygiene-push-force-safely"
          "git-hygiene-ssh-remotes"
          "git-workflow-cleanup-merged-branches"
          "git-workflow-curate-unpushed"
          "git-workflow-inspect-before-commit"
          "git-workflow-push-mode"
        ];

        # All git-hygiene-* skills: rules-of-thumb (commit/branch style,
        # safe force-push, SSH-by-default).
        agent-skills-git-hygiene = [
          "git-hygiene-branch-naming"
          "git-hygiene-commit-message-format"
          "git-hygiene-conventional-commits"
          "git-hygiene-gitignore"
          "git-hygiene-no-history-in-code"
          "git-hygiene-push-force-safely"
          "git-hygiene-ssh-remotes"
        ];

        # All git-workflow-* skills: interactive / multi-step procedures.
        agent-skills-git-workflow = [
          "git-workflow-cleanup-merged-branches"
          "git-workflow-curate-unpushed"
          "git-workflow-inspect-before-commit"
          "git-workflow-push-mode"
        ];

        # All 10 github-* skills (includes the agent-tagged trio).
        agent-skills-github-all = [
          "github-hygiene-gh-cli-gotchas"
          "github-hygiene-pull-request-mirrors-commit"
          "github-policy-auto-delete-merged-branches"
          "github-policy-codeowners"
          "github-policy-merge-commits-only"
          "github-policy-protect-default-branch"
          "github-pull-request-changeset-prompt"
          "github-pull-request-stacked"
          "github-pull-request-status-line"
          "github-pull-request-watcher"
        ];

        # All github-hygiene-* skills: PR-shape discipline + `gh` CLI gotchas.
        agent-skills-github-hygiene = [
          "github-hygiene-gh-cli-gotchas"
          "github-hygiene-pull-request-mirrors-commit"
        ];

        # All github-policy-* skills: one-time repo configuration.
        agent-skills-github-policy = [
          "github-policy-auto-delete-merged-branches"
          "github-policy-codeowners"
          "github-policy-merge-commits-only"
          "github-policy-protect-default-branch"
        ];

        # All github-pull-request-* skills: PR lifecycle / agent behavior.
        agent-skills-github-pull-request = [
          "github-pull-request-changeset-prompt"
          "github-pull-request-stacked"
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

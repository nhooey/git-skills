{
  description = "skills-git: Claude Code skills marketplace as a Nix flake (git hygiene, GitHub repo settings, agent PR lifecycle)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # `flake-skills` is the builder library, not a skill — it turns skill
    # directories into installable flakes and aggregates them.
    flake-skills = {
      url = "github:nhooey/flake-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Sources for the authoring-only skill set installed into this repo's dev
    # shell (nix-*, humanizer, skill-creator, superpowers). Aggregated as plain
    # Nix via ./skills-authoring/default.nix — lifted here as direct inputs (all
    # `github:` refs, no `path:`) so skills-git stays Garnix-safe when consumed
    # transitively. The sibling ./skills-authoring/flake.nix is the standalone
    # `?dir=skills-authoring` face.
    skills-nix = {
      url = "github:nhooey/skills-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-skills.follows = "flake-skills";
      };
    };
    humanizer = {
      url = "github:nhooey/skillspkgs?dir=pkgs/humanizer";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-skills.follows = "flake-skills";
      };
    };
    skill-creator = {
      url = "github:nhooey/skillspkgs?dir=pkgs/skill-creator";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-skills.follows = "flake-skills";
      };
    };
    superpowers = {
      url = "github:nhooey/skillspkgs?dir=pkgs/superpowers";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-skills.follows = "flake-skills";
      };
    };
  };

  outputs =
    {
      nixpkgs,
      flake-parts,
      flake-skills,
      ...
    }@inputs:
    let
      # The skills this repo outputs: every skill under ./skills built into
      # per-skill packages (consumed by `packs`/`mkEnv` below) plus the base
      # install/preview apps. Authoring-only skills are aggregated separately —
      # see `authoring` below.
      base = flake-skills.lib.mkAllSkillsFlake {
        inherit nixpkgs;
        skillsDir = ./skills;
        packagePrefix = "agent-skill-";
      };

      # Authoring-only skill aggregate, imported as plain Nix (no `path:` input)
      # from its canonical module; consumed by the dev shell startup below.
      authoring = import ./skills-authoring/default.nix {
        inherit (inputs)
          nixpkgs
          flake-skills
          skills-nix
          humanizer
          skill-creator
          superpowers
          ;
      };

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
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [
        inputs.devshell.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      # Expose the declarative reconcile one-liner (system -> shell snippet at
      # --scope=project) so consumers like skillspkgs' dev shell can install
      # this pack with the same idiom the aggregate flakes use, instead of
      # reaching into apps.reconcile.program and appending the scope flag.
      flake.reconcileScript = base.reconcileScript;

      perSystem =
        { system, ... }:
        {
          packages =
            base.packages.${system}
            // builtins.mapAttrs (packName: skillNames: mkEnv system packName skillNames) packs;

          apps = base.apps.${system};

          # Auto-reconcile skills at project scope on `nix develop`: this
          # repo's own skills (dogfooded) and the authoring-only tools from
          # the skills-authoring aggregate, each in its own named startup
          # hook (mirroring skillspkgs). Both are declarative + idempotent and
          # own disjoint reconcile appNames (base = `agent-skills-all`,
          # authoring = `skills-git-authoring`), so they coexist in one scope —
          # each sweeps only its own strays — and re-entry won't clobber the
          # other or other scopes.
          devshells.default = {
            name = "skills-git";
            motd = ''
              {bold}{14}🚀 Entering skills-git dev shell{reset}
              Run {bold}menu{reset} to list available commands.
            '';
            devshell.startup.install-git-skills.text = ''
              ${base.reconcileScript system}
            '';
            devshell.startup.install-authoring-skills.text = ''
              ${authoring.reconcileScript system}
            '';
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              shfmt.enable = true;
              yamlfmt.enable = true;
            };
          };
        };
    };
}

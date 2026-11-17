{
  description = "git-skills: Claude Code skills marketplace as a Nix flake (git hygiene, GitHub repo settings, agent PR lifecycle)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Read only for `lib.mkClaudePlugin`, which builds `hooks-plugin`. A
    # plain source, not a flake: agent-plugins-nixpkgs takes this repository
    # as an input to pass `hooks-plugin` through, and a flake input here
    # would make the two lock files nest each other at every update.
    agent-plugins-nixpkgs = {
      url = "github:nhooey/agent-plugins-nixpkgs";
      flake = false;
    };
    # `agent-skill-flake` is the builder library, not a skill — it turns skill
    # directories into installable flakes and aggregates them, and also exports
    # `flakeModules.devshellSkills` (which bundles numtide/devshell), so this
    # flake needs no `devshell` input of its own.
    agent-skill-flake = {
      url = "github:nhooey/agent-skill-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      flake-parts,
      agent-skill-flake,
      ...
    }@inputs:
    let
      # The skills this repo outputs: every skill under ./skills built into
      # per-skill packages (consumed by `packs`/`mkEnv` below) plus the base
      # install/preview apps.
      base = agent-skill-flake.lib.mkAllSkillsFlake {
        inherit nixpkgs;
        source = import ./source.nix;
        skillsDir = ./skills;
        packagePrefix = "agent-skill-";
      };

      packs = {
        # All 12 git-* skills.
        agent-skills-nhooey-git-all = [
          "git-hygiene-avoid-sweeping-operations"
          "git-hygiene-branch-naming"
          "git-hygiene-commit-message-format"
          "git-hygiene-conventional-commits"
          "git-hygiene-gitignore"
          "git-hygiene-no-history-in-tracked-files"
          "git-hygiene-push-force-safely"
          "git-hygiene-ssh-remotes"
          "git-workflow-curate-unpushed"
          "git-workflow-inspect-before-commit"
          "git-workflow-push-mode"
          "git-workflow-tidy-branches"
        ];

        # All git-hygiene-* skills: rules-of-thumb (commit/branch style,
        # safe force-push, no sweeping commands, SSH-by-default).
        agent-skills-nhooey-git-hygiene = [
          "git-hygiene-avoid-sweeping-operations"
          "git-hygiene-branch-naming"
          "git-hygiene-commit-message-format"
          "git-hygiene-conventional-commits"
          "git-hygiene-gitignore"
          "git-hygiene-no-history-in-tracked-files"
          "git-hygiene-push-force-safely"
          "git-hygiene-ssh-remotes"
        ];

        # All git-workflow-* skills: interactive / multi-step procedures.
        agent-skills-nhooey-git-workflow = [
          "git-workflow-curate-unpushed"
          "git-workflow-inspect-before-commit"
          "git-workflow-push-mode"
          "git-workflow-tidy-branches"
        ];

        # All 14 github-* skills (includes the agent-tagged ones).
        agent-skills-nhooey-github-all = [
          "github-hygiene-gh-cli-gotchas"
          "github-hygiene-pull-request-mirrors-commit"
          "github-hygiene-refer-to-issues-and-pull-requests"
          "github-hygiene-single-commit-pull-requests"
          "github-policy-auto-delete-merged-branches"
          "github-policy-codeowners"
          "github-policy-merge-commits-only"
          "github-policy-protect-default-branch"
          "github-workflow-browser-draft-preview"
          "github-workflow-pull-request-changeset-prompt"
          "github-workflow-pull-request-stacked"
          "github-workflow-pull-request-status-line"
          "github-workflow-pull-request-watcher"
          "github-workflow-repo-activity"
        ];

        # All github-hygiene-* skills: PR-shape discipline, issue/PR references + `gh` CLI gotchas.
        agent-skills-nhooey-github-hygiene = [
          "github-hygiene-gh-cli-gotchas"
          "github-hygiene-pull-request-mirrors-commit"
          "github-hygiene-refer-to-issues-and-pull-requests"
          "github-hygiene-single-commit-pull-requests"
        ];

        # All github-policy-* skills: one-time repo configuration.
        agent-skills-nhooey-github-policy = [
          "github-policy-auto-delete-merged-branches"
          "github-policy-codeowners"
          "github-policy-merge-commits-only"
          "github-policy-protect-default-branch"
        ];

        # All github-workflow-* skills: PR lifecycle, browser drafting, repo activity / agent
        # behavior.
        agent-skills-nhooey-github-workflow = [
          "github-workflow-browser-draft-preview"
          "github-workflow-pull-request-changeset-prompt"
          "github-workflow-pull-request-stacked"
          "github-workflow-pull-request-status-line"
          "github-workflow-pull-request-watcher"
          "github-workflow-repo-activity"
        ];
      };

      # Build an `agent-skill-flake.lib.mkSkillsEnv` for one (packName,
      # skillNames) pair. The env keeps the same `nix run`/`nix build`
      # UX as a plain `symlinkJoin`, but also carries the
      # `passthru.isFlakeSkillsEnv` + `flakeSkillsEnv` records that
      # `programs.agent-skill-flake.skills` needs to expand the env back
      # into per-skill records on home-manager activation.
      # A pack list is bare skill names; `base.bySkillName` indexes the
      # per-skill drvs by that stable identity, independent of the key namespace.
      mkEnv =
        system: packName: skillNames:
        agent-skill-flake.lib.mkSkillsEnv {
          pkgs = nixpkgs.legacyPackages.${system};
          name = packName;
          skills = builtins.map (n: base.bySkillName.${system}.${n}) skillNames;
        };

      claudePlugins = import "${inputs.agent-plugins-nixpkgs}/lib" { inherit (nixpkgs) lib; };

      # The hook scripts the `git-skills-hooks` plugin runs. Each stays in
      # its skill's scripts/, where the skill documents it and the checks
      # test it; the package copies it into the plugin's scripts/, and
      # plugin/hooks/hooks.json runs it from there.
      hookScripts = [
        ./skills/github-hygiene-pull-request-mirrors-commit/scripts/pull-request-sync-check.sh
      ];
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [
        # Bundles numtide/devshell + the whole dev-shell skills convention (the
        # stock motd, the install-skills startup that reconciles the runtime
        # skills-devshell/ sub-flake, the ci/dev/maintenance command trio, and
        # the reap-skills/update-skills-devshell pair). Configured via the
        # `agent-skill-flake.devshellSkills` options block below.
        inputs.agent-skill-flake.flakeModules.devshellSkills
        inputs.treefmt-nix.flakeModule
      ];

      # git-skills keeps the stock banner ("🚀 Entering git-skills dev shell"),
      # so only `name` is set — the module generates the motd from it.
      agent-skill-flake.devshellSkills.name = "git-skills";

      # Expose the declarative reconcile one-liner (system -> shell snippet at
      # --scope=project) so consumers like skillspkgs' dev shell can install
      # this pack with the same idiom the aggregate flakes use, instead of
      # reaching into apps.reconcile.program and appending the scope flag.
      flake.reconcileScript = base.reconcileScript;

      perSystem =
        { pkgs, system, ... }:
        let
          # `git-skills` (scripts/git_skills.py) runs the skills' checks; the
          # dev shell's menu lists it and `nix flake check` runs it below.
          git-skills = pkgs.writeShellApplication {
            name = "git-skills";
            runtimeInputs = [ pkgs.python3 ];
            text = ''exec python3 -B ${./scripts/git_skills.py} "$@"'';
          };

          # `git-skills-hooks`: a hooks-only Claude Code plugin, installed
          # through agent-plugins-nixpkgs.
          hooks-plugin = claudePlugins.mkClaudePlugin pkgs {
            src = ./plugin;
            postPatch = ''
              mkdir -p scripts
              ${pkgs.lib.concatMapStrings (script: ''
                cp ${script} scripts/${builtins.baseNameOf script}
              '') hookScripts}
            '';
          };
        in
        {
          # `base.packages` (mkAllSkillsFlake without a `name =`) carries a
          # `default` alias and the owner-wide `agent-skills-nhooey-all`
          # aggregate. That owner-`all` is unresolvable — no single repo holds
          # all of nhooey's skills — and collides across every nhooey repo under
          # skillspkgs / nur-packages' last-write-wins `//` merge, so strip both
          # and expose only the `agent-skill-nhooey-*` per-skill keys plus the
          # owner+topic packs below.
          packages =
            (builtins.removeAttrs base.packages.${system} [
              "default"
              "agent-skills-nhooey-all"
            ])
            // builtins.mapAttrs (packName: skillNames: mkEnv system packName skillNames) packs
            // {
              inherit git-skills hooks-plugin;
            };

          apps = base.apps.${system};

          devshells.default.commands = [
            {
              category = "ci";
              name = "git-skills";
              help = "Test and lint the skills: git-skills test|lint|list [SKILL...]";
              package = git-skills;
            }
          ];

          # Every skill's bundled unittest suite, the skills' frontmatter, and
          # the tool's own tests. `git` is for tidy-branches' git-side tests,
          # `git` and `jq` for the pull request sync check hook's tests.
          # `hooks-plugin` checks the built plugin's manifest and hooks.json,
          # and that each Bash hook stays silent for a command it ignores.
          checks =
            builtins.mapAttrs
              (
                name: command:
                pkgs.runCommand "git-skills-${name}"
                  {
                    nativeBuildInputs = [
                      git-skills
                      pkgs.git
                      pkgs.jq
                      pkgs.python3
                    ];
                  }
                  ''
                    export HOME="$TMPDIR"
                    ${command}
                    touch "$out"
                  ''
              )
              {
                skill-tests = "git-skills --root ${./.} test";
                skill-lint = "git-skills --root ${./.} lint";
                tool-tests = "cd ${./scripts} && python3 -B -m unittest discover --verbose";
                hooks-plugin = "bash ${./scripts/check-hooks-plugin.sh} ${hooks-plugin} git-skills-hooks";
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

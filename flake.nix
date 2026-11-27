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
        # create-or-update-pull-request.sh runs a Babashka program; the
        # built skill's scripts find it and the tools it runs without the
        # user installing them.
        scriptInputs.github-hygiene-pull-request-mirrors-commit = prBodyInputs;
      };

      prBodyInputs = import ./skills/github-hygiene-pull-request-mirrors-commit/script-inputs.nix;

      packs = {
        # All 13 git-* skills.
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
          "git-workflow-tidy-worktrees"
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
          "git-workflow-tidy-worktrees"
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
        ./skills/github-hygiene-pull-request-mirrors-commit/scripts/pull-request-write-guard.sh
      ];

      # The PR body program the hooks run, copied beside them: the Bash
      # entry point and the Babashka project it starts. The write guard
      # names the entry point in its denial, so it gets `bb` too.
      mirrorsCommitScripts = ./skills/github-hygiene-pull-request-mirrors-commit/scripts;
      hookPrograms = [
        "create-or-update-pull-request.sh"
        "bb.edn"
        "src"
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
          # The tests' Python, with the libraries the tests import. The
          # skills' own scripts import only the standard library.
          testPython = pkgs.python3.withPackages (ps: [ ps.pytest ]);

          # The languages of the tests in tests/, each run by its own tool.
          testLanguages = [
            "python"
            "bats"
            "clojure"
          ];

          # `git-skills test [--language LANGUAGE] [SKILL...]`, the shell
          # script scripts/git-skills.sh, runs the tests in tests/, or in
          # each named skill's folder there, with each language's own
          # tool: pytest for Python, bats for `.bats` files, and `bb test`
          # for a Babashka project's clojure.test tests. Other commands go
          # to scripts/git_skills.py, which parses SKILL.md frontmatter
          # with yq-go. The dev shell's menu lists it, and `nix flake check`
          # runs it once per language.
          git-skills = pkgs.writeShellApplication {
            name = "git-skills";
            runtimeInputs = prBodyInputs pkgs ++ [
              testPython
              pkgs.bats
              pkgs.git
              pkgs.jq
              pkgs.yq-go
            ];
            # The script's two values from Nix: the lint program, and the
            # test languages the checks below are generated from.
            runtimeEnv = {
              GIT_SKILLS_PROGRAM = "${./scripts/git_skills.py}";
              GIT_SKILLS_TEST_LANGUAGES = builtins.toString testLanguages;
            };
            text = builtins.readFile ./scripts/git-skills.sh;
          };

          # The files the `git-skills-hooks` plugin's scripts/ holds, each
          # under its own name: the hook scripts and the PR body program.
          hookFiles = pkgs.linkFarm "git-skills-hook-files" (
            builtins.map (name: {
              inherit name;
              path = "${mirrorsCommitScripts}/${name}";
            }) hookPrograms
            ++ builtins.map (script: {
              name = builtins.baseNameOf script;
              path = script;
            }) hookScripts
          );

          # `git-skills-hooks`: a hooks-only Claude Code plugin, installed
          # through agent-plugins-nixpkgs: the PostToolUse sync check and
          # the PreToolUse write guard. scripts/copy-hook-scripts.sh copies
          # them in and puts the PR body program's tools on each one's
          # PATH, for the program it runs.
          hooks-plugin = claudePlugins.mkClaudePlugin pkgs {
            src = ./plugin;
            postPatch = "bash ${./scripts/copy-hook-scripts.sh} ${hookFiles} ${pkgs.lib.makeBinPath (prBodyInputs pkgs)}";
          };

          # A directory for a global `core.hooksPath`: the `pre-push` hook
          # that refuses rewriting a remote's default branch, and for every
          # other hook this git documents one that runs the repository's own.
          git-push-force-safely-hooks = pkgs.runCommand "git-push-force-safely-hooks" { } ''
            bash ${./scripts/write-forwarding-hooks.sh} \
              ${./skills/git-hygiene-push-force-safely/scripts} "$out" \
              ${pkgs.git}/share/man/man5/githooks.5.gz
          '';
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
              inherit git-skills hooks-plugin git-push-force-safely-hooks;
            };

          apps = base.apps.${system};

          # The test tools, for running one suite by hand: `pytest`, `bats`,
          # the PR body program's `bb`, and `yq` for the lint's tests.
          devshells.default.packages = prBodyInputs pkgs ++ [
            testPython
            pkgs.bats
            pkgs.yq-go
          ];

          devshells.default.commands = [
            {
              category = "ci";
              name = "git-skills";
              help = "Test and lint the skills: git-skills test|lint [SKILL...]";
              package = git-skills;
            }
          ];

          # `tests-python`, `tests-bats` and `tests-clojure` each run one
          # language's tests in tests/ with its own tool, through the same
          # `git-skills test --language` the dev shell runs; `skill-lint`
          # checks the skills' frontmatter.
          # `hooks-plugin` checks the built plugin's manifest and
          # hooks.json, and that each Bash hook stays silent for a command
          # it ignores, with `git`, `jq` and the PR body program's tools;
          # `hooks-plugin-bb` that its write guard finds `bb` with no PATH
          # at all.
          checks =
            builtins.mapAttrs
              (
                name: command:
                pkgs.runCommand "git-skills-${name}"
                  {
                    nativeBuildInputs = prBodyInputs pkgs ++ [
                      git-skills
                      pkgs.git
                      pkgs.jq
                    ];
                  }
                  ''
                    export HOME="$TMPDIR"
                    ${command}
                    touch "$out"
                  ''
              )
              (
                builtins.listToAttrs (
                  builtins.map (language: {
                    name = "tests-${language}";
                    value = "PRJ_ROOT=${./.} git-skills test --language ${language}";
                  }) testLanguages
                )
                // {
                  skill-lint = "git-skills --root ${./.} lint";
                  hooks-plugin = "bash ${./scripts/check-hooks-plugin.sh} ${hooks-plugin} git-skills-hooks";
                  hooks-plugin-bb = "bash ${./scripts/check-hooks-plugin-bb.sh} ${hooks-plugin}";
                }
              );

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

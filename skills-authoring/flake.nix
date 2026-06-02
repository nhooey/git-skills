{
  description = "skills-git authoring skills: third-party Claude Code skills installed into the skills-git dev shell for authoring this repo — deliberately kept separate from the skills this repo outputs.";

  # Standalone `?dir=skills-authoring` face only. The parent skills-git flake
  # never reads this — it plain-`import`s ./default.nix (see that file's header),
  # passing the same source inputs lifted into its own flake. These inputs +
  # flake.lock pin the aggregate for direct `?dir=` use.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # `flake-skills` is the builder library, not a skill — it provides
    # `mkAggregateSkillsFlake`. Followed by the parent flake so both share
    # one evaluation.
    flake-skills = {
      url = "github:nhooey/flake-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Every input below this divider is a skill source.
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
      flake-skills,
      skills-nix,
      humanizer,
      skill-creator,
      superpowers,
      ...
    }:
    {
      # The new aggregate interface. The parent flake consumes `reconcileScript`
      # (`system -> string`, a one-liner that converges the project-scope skills
      # dir to exactly this union) in its dev shell startup. `packages` / `apps`
      # are surfaced for `nix eval`/`nix run` inspection of the cherry-picked set.
      inherit
        (import ./default.nix {
          inherit
            nixpkgs
            flake-skills
            skills-nix
            humanizer
            skill-creator
            superpowers
            ;
        })
        packages
        apps
        reconcileScript
        ;
    };
}

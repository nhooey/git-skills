{
  description = "skills-git authoring skills: third-party Claude Code skills installed into the skills-git dev shell for authoring this repo — deliberately kept separate from the skills this repo outputs.";

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
    let
      # No `skillsDir`: this flake outputs no skills of its own, it only
      # aggregates external sources so the parent flake can install them.
      # A source with no `skills` installs all of it; `skills = [ ... ]`
      # cherry-picks; `prefix` namespaces the pack to avoid name clashes.
      agg = flake-skills.lib.mkAggregateSkillsFlake {
        inherit nixpkgs;
        packagePrefix = "agent-skill-";
        sources = [
          {
            source = skills-nix;
            skills = [
              "nix-flakes"
              "nix-garnix-ci"
            ];
          }
          { source = humanizer; }
          {
            source = skill-creator;
            prefix = "anthropic";
          }
          {
            source = superpowers;
            prefix = "superpowers";
          }
        ];
      };
    in
    {
      # The sole consumed output: `system -> string`, the newline-joined
      # install commands for these authoring skills. The parent flake drops
      # it into its dev shell startup.
      inherit (agg) installScript;
    };
}

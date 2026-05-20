{
  description = "git-branch-naming: Claude Code skill — long, descriptive, dash-separated, autocomplete-friendly branch names";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills.url = "github:nhooey/flake-skills";
    flake-skills.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, flake-skills, ... }:
    flake-skills.lib.mkSkillFlake {
      inherit nixpkgs;
      skillName = "git-branch-naming";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

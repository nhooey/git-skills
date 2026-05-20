{
  description = "git-conventional-commits: Claude Code skill — type(scope): subject for Conventional Commits-using repos";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills.url = "github:nhooey/flake-skills";
    flake-skills.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, flake-skills, ... }:
    flake-skills.lib.mkSkillFlake {
      inherit nixpkgs;
      skillName = "git-conventional-commits";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

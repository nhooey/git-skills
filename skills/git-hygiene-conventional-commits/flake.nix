{
  description = "git-hygiene-conventional-commits: Claude Code skill — type(scope): subject for Conventional Commits-using repos";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills = {
      url = "github:nhooey/flake-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, flake-skills, ... }:
    flake-skills.lib.mkSkillFlake {
      inherit nixpkgs;
      skillName = "git-hygiene-conventional-commits";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

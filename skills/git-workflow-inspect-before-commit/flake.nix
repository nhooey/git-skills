{
  description = "git-workflow-inspect-before-commit: Claude Code skill — inspect/stage/review (git status/diff/diff --cached) before every commit";

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
      skillName = "git-workflow-inspect-before-commit";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

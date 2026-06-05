{
  description = "git-workflow-inspect-before-commit: Claude Code skill — inspect/stage/review (git status/diff/diff --cached) before every commit";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agent-skill-flake = {
      url = "github:nhooey/agent-skill-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, agent-skill-flake, ... }:
    agent-skill-flake.lib.mkSkillFlake {
      inherit nixpkgs;
      source = import ../../source.nix;
      skillName = "git-workflow-inspect-before-commit";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

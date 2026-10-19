{
  description = "github-workflow-repo-activity: Claude Code skill — list a GitHub user's comments, reviews, merges, pushes and branches on a repo since a time, without the Events API";

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
      skillName = "github-workflow-repo-activity";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

{
  description = "github-workflow-pull-request-watcher: Claude Code skill — background Monitor that polls PR check-runs/comments/state and reacts to each event";

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
      skillName = "github-workflow-pull-request-watcher";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

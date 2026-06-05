{
  description = "github-workflow-pull-request-status-line: Claude Code skill — surface PRs as `<status-circle> <url> — **PR #<num>: <title>**` with live state";

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
      skillName = "github-workflow-pull-request-status-line";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

{
  description = "github-hygiene-single-commit-pull-requests: Claude Code skill — one commit per PR, several only for a reason named in the preferences and declared in a Multi-commit trailer";

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
      skillName = "github-hygiene-single-commit-pull-requests";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

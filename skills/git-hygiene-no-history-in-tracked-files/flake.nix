{
  description = "git-hygiene-no-history-in-tracked-files: Claude Code skill — tracked files state the current state; history goes in commit messages";

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
      skillName = "git-hygiene-no-history-in-tracked-files";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

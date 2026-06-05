{
  description = "github-policy-merge-commits-only: Claude Code skill — disable squash and rebase merges; every PR lands as a merge commit";

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
      skillName = "github-policy-merge-commits-only";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

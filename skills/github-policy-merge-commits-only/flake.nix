{
  description = "github-policy-merge-commits-only: Claude Code skill — disable squash and rebase merges; every PR lands as a merge commit";

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
      source = import ../../source.nix;
      skillName = "github-policy-merge-commits-only";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

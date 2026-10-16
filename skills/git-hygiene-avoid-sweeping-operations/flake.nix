{
  description = "git-hygiene-avoid-sweeping-operations: Claude Code skill — name the paths and refs a git command acts on, never sweep the whole tree";

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
      skillName = "git-hygiene-avoid-sweeping-operations";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

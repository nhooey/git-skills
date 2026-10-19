{
  description = "git-workflow-tidy-branches: Claude Code skill — report and apply branch cleanups: delete merged branches, rebase clean ones onto the base, flag the rest";

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
      skillName = "git-workflow-tidy-branches";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

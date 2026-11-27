{
  description = "github-policy-no-hosted-ci: Claude Code skill — no GitHub Actions or Garnix config; nix flake check, run locally, is the test";

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
      skillName = "github-policy-no-hosted-ci";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

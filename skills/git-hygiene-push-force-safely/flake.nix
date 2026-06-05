{
  description = "git-hygiene-push-force-safely: Claude Code skill — always force-push with --force-with-lease, never plain --force";

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
      skillName = "git-hygiene-push-force-safely";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

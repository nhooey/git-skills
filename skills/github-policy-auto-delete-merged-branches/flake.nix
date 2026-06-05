{
  description = "github-policy-auto-delete-merged-branches: Claude Code skill — enable delete_branch_on_merge so PR head branches vanish on merge";

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
      skillName = "github-policy-auto-delete-merged-branches";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

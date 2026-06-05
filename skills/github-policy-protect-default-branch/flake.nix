{
  description = "github-policy-protect-default-branch: Claude Code skill — apply Rulesets-API branch protection (require PR, status checks, block force-push, block deletion)";

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
      skillName = "github-policy-protect-default-branch";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

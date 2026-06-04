{
  description = "github-policy-protect-default-branch: Claude Code skill — apply Rulesets-API branch protection (require PR, status checks, block force-push, block deletion)";

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
      skillName = "github-policy-protect-default-branch";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

{
  description = "github-policy-codeowners: Claude Code skill — set up .github/CODEOWNERS and require_code_owner_review for multi-contributor repos";

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
      skillName = "github-policy-codeowners";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

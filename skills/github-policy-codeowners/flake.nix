{
  description = "github-policy-codeowners: Claude Code skill — set up .github/CODEOWNERS and require_code_owner_review for multi-contributor repos";

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
      skillName = "github-policy-codeowners";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

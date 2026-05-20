{
  description = "github-codeowners: Claude Code skill — set up .github/CODEOWNERS and require_code_owner_review for multi-contributor repos";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills.url = "github:nhooey/flake-skills";
    flake-skills.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, flake-skills, ... }:
    flake-skills.lib.mkSkillFlake {
      inherit nixpkgs;
      skillName = "github-codeowners";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

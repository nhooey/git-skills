{
  description = "github-protect-default-branch: Claude Code skill — apply Rulesets-API branch protection (require PR, status checks, block force-push, block deletion)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills.url = "github:nhooey/flake-skills";
    flake-skills.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, flake-skills, ... }:
    flake-skills.lib.mkSkillFlake {
      inherit nixpkgs;
      skillName = "github-protect-default-branch";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

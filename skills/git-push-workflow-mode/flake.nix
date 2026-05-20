{
  description = "git-push-workflow-mode: Claude Code skill — pick direct-to-main / PR-always / ask-each-time once per repo; saved to project memory so future sessions don't re-ask";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills.url = "github:nhooey/flake-skills";
    flake-skills.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, flake-skills, ... }:
    flake-skills.lib.mkSkillFlake {
      inherit nixpkgs;
      skillName = "git-push-workflow-mode";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

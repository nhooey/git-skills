{
  description = "git-workflow-push-mode: Claude Code skill — pick direct-to-main / PR-always / ask-each-time once per repo; saved to project memory so future sessions don't re-ask";

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
      skillName = "git-workflow-push-mode";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

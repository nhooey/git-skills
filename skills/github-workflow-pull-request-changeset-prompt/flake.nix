{
  description = "github-workflow-pull-request-changeset-prompt: Claude Code skill — multi-select AskUserQuestion after every change-set (Stage/Commit/Amend/Push/Force/Open-PR/Re-derive/Monitor)";

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
      skillName = "github-workflow-pull-request-changeset-prompt";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

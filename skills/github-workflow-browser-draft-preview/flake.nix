{
  description = "github-workflow-browser-draft-preview: Claude Code skill — draft GitHub PRs and comments in Chrome, switch to Preview, box the draft in red, raise the tab and ask before posting";

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
      skillName = "github-workflow-browser-draft-preview";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

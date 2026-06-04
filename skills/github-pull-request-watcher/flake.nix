{
  description = "github-pull-request-watcher: Claude Code skill — background Monitor that polls PR check-runs/comments/state and reacts to each event";

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
      skillName = "github-pull-request-watcher";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

{
  description = "github-pull-request-status-line: Claude Code skill — surface PRs as `<status-circle> <url> — **PR #<num>: <title>**` with live state";

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
      skillName = "github-pull-request-status-line";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

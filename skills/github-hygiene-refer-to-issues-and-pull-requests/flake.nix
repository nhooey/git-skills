{
  description = "github-hygiene-refer-to-issues-and-pull-requests: Claude Code skill — refer to GitHub issues, PRs and commits by number plus title, linked; branch names only in parentheses after their PR";

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
      skillName = "github-hygiene-refer-to-issues-and-pull-requests";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

{
  description = "git-hygiene-no-history-in-code: Claude Code skill — keep diachronic notes out of source; put them in commit messages";

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
      skillName = "git-hygiene-no-history-in-code";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

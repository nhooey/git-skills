{
  description = "git-hygiene-no-history-in-code: Claude Code skill — keep diachronic notes out of source; put them in commit messages";

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
      skillName = "git-hygiene-no-history-in-code";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

{
  description = "git-no-history-in-code: Claude Code skill — keep diachronic notes out of source; put them in commit messages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills.url = "github:nhooey/flake-skills/configurable-package-prefix";
    flake-skills.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, flake-skills, ... }:
    flake-skills.lib.mkSkillFlake {
      inherit nixpkgs;
      skillName = "git-no-history-in-code";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

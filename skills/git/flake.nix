{
  description = "git: Claude Code skill for opinionated Git hygiene (commit messages, history cleanliness, force-push safety, branch naming, post-merge cleanup, .gitignore discipline)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills.url = "github:nhooey/flake-skills";
    flake-skills.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, flake-skills, ... }:
    flake-skills.lib.mkSkillFlake {
      inherit nixpkgs;
      skillName = "git";
      src = ./.;
    };
}

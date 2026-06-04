{
  description = "github-hygiene-gh-cli-gotchas: Claude Code skill — passive reference for known traps in the gh CLI (pr edit exits 1, --json merged invalid, self-approval blocked, rename closes PRs)";

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
      skillName = "github-hygiene-gh-cli-gotchas";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

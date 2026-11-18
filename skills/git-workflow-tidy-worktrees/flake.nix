{
  description = "git-workflow-tidy-worktrees: Claude Code skill — tidy git worktrees with the worktrees program: when to sweep, finish or clean, and what never goes without the user's word";

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
      skillName = "git-workflow-tidy-worktrees";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

{
  description = "github-workflow-pull-request-stacked: Claude Code skill — submit dependent PRs on GitHub; covers repos you control (`gt submit --stack`, merge bottom-first, `gt sync`), upstream fork-only (draft + Depends-on), and upstream with topic-branch push grant";

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
      skillName = "github-workflow-pull-request-stacked";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

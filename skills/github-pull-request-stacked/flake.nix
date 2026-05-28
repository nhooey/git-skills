{
  description = "github-pull-request-stacked: Claude Code skill — submit dependent PRs on GitHub; covers repos you control (`gt submit --stack`, merge bottom-first, `gt sync`), upstream fork-only (draft + Depends-on), and upstream with topic-branch push grant";

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
      skillName = "github-pull-request-stacked";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

{
  description = "github-workflow-pull-request-stacked: Claude Code skill — submit dependent PRs on GitHub; covers repos you control (`gh stack submit`, merge the top PR, `gh stack sync`; `gt` for branching stacks), upstream fork-only (draft + Depends-on, `git rebase --update-refs`), and upstream with topic-branch push grant (`gh stack` or `gt`)";

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

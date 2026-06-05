{
  description = "git-workflow-cleanup-merged-branches: Claude Code skill — delete local/remote merged branches; ask before bulk-pruning";

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
      skillName = "git-workflow-cleanup-merged-branches";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

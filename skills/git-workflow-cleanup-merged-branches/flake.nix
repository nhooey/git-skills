{
  description = "git-workflow-cleanup-merged-branches: Claude Code skill — delete local/remote merged branches; ask before bulk-pruning";

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
      skillName = "git-workflow-cleanup-merged-branches";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

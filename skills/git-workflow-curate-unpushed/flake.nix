{
  description = "git-workflow-curate-unpushed: Claude Code skill — squash noise + amend forward to curate unpushed history";

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
      skillName = "git-workflow-curate-unpushed";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

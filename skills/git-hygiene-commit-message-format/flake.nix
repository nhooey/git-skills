{
  description = "git-hygiene-commit-message-format: Claude Code skill — subject under 72 chars, blank line, body wrapped at 72, why-not-what";

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
      skillName = "git-hygiene-commit-message-format";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

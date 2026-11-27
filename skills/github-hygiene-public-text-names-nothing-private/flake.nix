{
  description = "github-hygiene-public-text-names-nothing-private: Claude Code skill — public text never names a private repository, a person's private configuration or a home-directory path; check visibility before naming a repository, scan before pushing";

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
      skillName = "github-hygiene-public-text-names-nothing-private";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

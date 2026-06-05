{
  description = "git-hygiene-ssh-remotes: Claude Code skill — prefer SSH (git@github.com:owner/repo.git) over HTTPS for git remotes";

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
      skillName = "git-hygiene-ssh-remotes";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

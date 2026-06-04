{
  description = "git-hygiene-ssh-remotes: Claude Code skill — prefer SSH (git@github.com:owner/repo.git) over HTTPS for git remotes";

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
      skillName = "git-hygiene-ssh-remotes";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

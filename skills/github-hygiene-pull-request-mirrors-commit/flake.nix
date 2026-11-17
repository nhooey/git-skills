{
  description = "github-hygiene-pull-request-mirrors-commit: Claude Code skill — one commit per PR; title = subject, body = body, rendered by a Babashka program; re-sync title/body after every amend";

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
      skillName = "github-hygiene-pull-request-mirrors-commit";
      packagePrefix = "agent-skill-";
      src = ./.;
      # create-or-update-pull-request.sh runs a Babashka program, which
      # runs cmark-gfm and shfmt.
      scriptInputs = import ./script-inputs.nix;
    };
}

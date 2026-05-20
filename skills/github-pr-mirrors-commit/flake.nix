{
  description = "github-pr-mirrors-commit: Claude Code skill — one commit per PR; title = subject, body = body (unwrapped via fmt -w 2500); re-sync title/body after every amend";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills.url = "github:nhooey/flake-skills/configurable-package-prefix";
    flake-skills.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, flake-skills, ... }:
    flake-skills.lib.mkSkillFlake {
      inherit nixpkgs;
      skillName = "github-pr-mirrors-commit";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

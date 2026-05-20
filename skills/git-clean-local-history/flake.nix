{
  description = "git-clean-local-history: Claude Code skill — squash noise + amend forward to curate unpushed history";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills.url = "github:nhooey/flake-skills/configurable-package-prefix";
    flake-skills.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, flake-skills, ... }:
    flake-skills.lib.mkSkillFlake {
      inherit nixpkgs;
      skillName = "git-clean-local-history";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

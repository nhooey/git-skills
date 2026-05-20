{
  description = "github-auto-delete-merged-branches: Claude Code skill — enable delete_branch_on_merge so PR head branches vanish on merge";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills.url = "github:nhooey/flake-skills/configurable-package-prefix";
    flake-skills.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, flake-skills, ... }:
    flake-skills.lib.mkSkillFlake {
      inherit nixpkgs;
      skillName = "github-auto-delete-merged-branches";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

{
  description = "git-hygiene-gitignore: Claude Code skill — anchored paths, no personal preferences, compress patterns safely";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills.url = "github:nhooey/flake-skills";
    flake-skills.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, flake-skills, ... }:
    flake-skills.lib.mkSkillFlake {
      inherit nixpkgs;
      skillName = "git-hygiene-gitignore";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

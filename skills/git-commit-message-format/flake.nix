{
  description = "git-commit-message-format: Claude Code skill — subject under 72 chars, blank line, body wrapped at 72, why-not-what";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills.url = "github:nhooey/flake-skills";
    flake-skills.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, flake-skills, ... }:
    flake-skills.lib.mkSkillFlake {
      inherit nixpkgs;
      skillName = "git-commit-message-format";
      src = ./.;
    };
}

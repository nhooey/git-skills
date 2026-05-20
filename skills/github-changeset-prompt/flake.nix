{
  description = "github-changeset-prompt: Claude Code skill — multi-select AskUserQuestion after every change-set (Stage/Commit/Amend/Push/Force/Open-PR/Re-derive/Monitor)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-skills.url = "github:nhooey/flake-skills";
    flake-skills.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, flake-skills, ... }:
    flake-skills.lib.mkSkillFlake {
      inherit nixpkgs;
      skillName = "github-changeset-prompt";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

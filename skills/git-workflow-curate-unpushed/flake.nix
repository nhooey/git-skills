{
  description = "git-workflow-curate-unpushed: Claude Code skill — squash noise + amend forward to curate unpushed history";

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
      skillName = "git-workflow-curate-unpushed";
      packagePrefix = "agent-skill-";
      src = ./.;
    };
}

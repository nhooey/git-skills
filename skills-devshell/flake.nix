{
  description = "git-skills dev-shell skill set — an isolated sub-flake invoked at RUNTIME by the root devShell, never a root input. The skill sources live only in THIS flake's lock, so the root git-skills stays a leaf with zero dev-shell skill inputs and transitive consumers never drag the skill mesh in.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";

    # The builder lib; it carries no skill inputs.
    agent-skill-flake = {
      url = "github:nhooey/agent-skill-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # skillspkgs' per-family combinations. It follows `nixpkgs` but not
    # `agent-skill-flake`, so its sources keep their own compatible builder;
    # `mkDevshellSkillsFlake` below still runs from this flake's pinned lib.
    skillspkgs-combinations = {
      url = "github:nhooey/skillspkgs?dir=sources/combinations";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      agent-skill-flake,
      ...
    }@inputs:
    agent-skill-flake.lib.mkDevshellSkillsFlake {
      inherit nixpkgs;
      systems = import inputs.systems;
      name = "git-skills-devshell";
      sources = [
        # The skill-collections family's combination, the one skill set every
        # skill collection installs. Nothing is added: it already covers the
        # Python this repository's skills bundle.
        { source = inputs.skillspkgs-combinations.combinations.skill-collections; }
      ];
    };
}

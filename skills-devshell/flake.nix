{
  description = "git-skills dev-shell skill set — an isolated sub-flake invoked at RUNTIME by the root devShell, never a root input. The skill sources (skillspkgs' authoring-with-git combination) live only in THIS flake's lock, so the root git-skills stays a leaf with zero dev-shell skill inputs and transitive consumers never drag the skill mesh in.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";

    agent-skill-flake = {
      url = "github:nhooey/agent-skill-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # skillspkgs' curated `authoring-with-git` combination (nix + humanizer +
    # anthropic/daymade skill-creation + superpowers + the whole git/GitHub
    # pack — which already bundles git-skills' own skills, deduped into one
    # consistent set). This is the dev shell's entire skill set in one
    # combination, so it's the lone source.
    skillspkgs-combinations = {
      url = "github:nhooey/skillspkgs?dir=sources/combinations";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      agent-skill-flake,
      skillspkgs-combinations,
      ...
    }@inputs:
    agent-skill-flake.lib.mkDevshellSkillsFlake {
      inherit nixpkgs;
      systems = import inputs.systems;
      name = "git-skills-devshell";
      sources = [
        { source = skillspkgs-combinations.combinations.authoring-with-git; }
      ];
    };
}

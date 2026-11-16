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

    # Skill sources. They follow `nixpkgs` but not `agent-skill-flake`, so
    # each keeps its own compatible builder.
    coding-agent-skills = {
      url = "github:nhooey/coding-agent-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-skills = {
      url = "github:nhooey/git-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-skills = {
      url = "github:nhooey/nix-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    python-skills = {
      url = "github:nhooey/python-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    shell-skills = {
      url = "github:nhooey/shell-skills";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Third-party skills skillspkgs vendors, the skill-authoring tooling of
    # its `authoring` combination.
    humanizer = {
      url = "github:nhooey/skillspkgs?dir=pkgs/humanizer";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    skill-creator = {
      url = "github:nhooey/skillspkgs?dir=pkgs/skill-creator";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    superpowers = {
      url = "github:nhooey/skillspkgs?dir=pkgs/superpowers";
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
        # The repository's own git and GitHub skills, as a consumer sees them.
        { source = inputs.git-skills; }
        # Writing this flake and each skill's flake.
        {
          source = inputs.nix-skills;
          skills = [ "nix-flakes" ];
        }
        # The Python scripts some skills bundle.
        { source = inputs.python-skills; }
        # Safe shell commands: named deletes, PIDs, no machine-wide changes.
        { source = inputs.shell-skills; }
        # Running as a headless session in a checkout, keeping the scratchpad
        # tidy, and the cross-repository plan's graph.
        {
          source = inputs.coding-agent-skills;
          skills = [
            "coding-agent-headless-in-checkout"
            "coding-agent-plans-as-graph"
            "coding-agent-scratchpad-scripts"
          ];
        }
        # Writing and testing skills.
        { source = inputs.humanizer; }
        {
          source = inputs.skill-creator;
          prefix = "anthropic";
        }
        {
          source = inputs.superpowers;
          prefix = "superpowers";
        }
      ];
    };
}

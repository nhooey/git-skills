# Canonical skills-git authoring aggregate: third-party Claude Code skills
# installed into the skills-git dev shell for authoring this repo — deliberately
# kept separate from the skills this repo outputs. Imported as plain Nix by
# ../flake.nix (so it adds no `path:` input — keeping Garnix happy when skills-git
# is consumed transitively) and by the sibling ./flake.nix (the standalone
# `?dir=skills-authoring` face). Mirrors skillspkgs' sources/combinations layout.
#
# No `skillsDir`: this outputs no skills of its own, it only aggregates external
# sources so the parent flake can install them. A source with no `skills`
# installs all of it; `skills = [ ... ]` cherry-picks; `prefix` namespaces the
# pack to avoid name clashes.
{
  nixpkgs,
  flake-skills,
  skills-nix,
  humanizer,
  skill-creator,
  superpowers,
}:
flake-skills.lib.mkAggregateSkillsFlake {
  inherit nixpkgs;
  # Distinct ownership name so the declarative `reconcile` sweep is scoped to
  # *these* authoring skills. The parent skills-git flake installs its own base
  # skills into the same project-scope dir under the default `agent-skills-all`
  # appName; a different name here keeps each reconcile owning only its own slice
  # (an entry the lock attributes to another appName is left alone).
  name = "skills-git-authoring";
  packagePrefix = "agent-skill-";
  sources = [
    {
      source = skills-nix;
      skills = [
        "nix-flakes"
        "nix-garnix-ci"
      ];
    }
    { source = humanizer; }
    {
      source = skill-creator;
      prefix = "anthropic";
    }
    {
      source = superpowers;
      prefix = "superpowers";
    }
  ];
}

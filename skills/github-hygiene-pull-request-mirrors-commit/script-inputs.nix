# The tools the PR body program in scripts/ runs: `bb` for the program,
# `cmark-gfm` to parse commit bodies and preferences as Markdown, and
# `shfmt` for the write guard to parse a Bash command line. The skill's
# flake, the repository's flake and its hooks plugin all pin these.
pkgs: [
  pkgs.babashka
  pkgs.cmark-gfm
  pkgs.shfmt
]

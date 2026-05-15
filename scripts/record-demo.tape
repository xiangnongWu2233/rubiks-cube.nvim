# Records a demo of rubiks-cube.nvim's auto-solve feature using the user's
# REAL Neovim config (colorscheme, statusline, plugins).
#
# Storyboard:
#   open cube → scramble → a few manual moves → S → kociemba auto-solve
#   animation → a rotation combo (y y x x) to verify all faces are solved.
#
# Prerequisites (one-time setup):
#   1. In your lazy spec for rubiks-cube.nvim (e.g. plugins/games.lua),
#      add `dir = "<absolute path to this working dir>"` so lazy loads
#      from your local checkout instead of GitHub. Without this, the
#      recorded demo runs against the v0.1 GitHub release and `S` does
#      nothing (no auto-solve in that version).
#   2. kociemba on $PATH (see README's Auto-solve section).
#
# Run from the plugin root:
#     vhs scripts/record-demo.tape
#
# Produces assets/demo.gif + assets/demo.mp4.

Output assets/demo.gif
Output assets/demo.mp4

Set FontSize 20
# Width 2000 gives the vhs terminal ~138 cols at FontSize 20 (cell width
# is ~14.4 px). The cube's floating window then renders ~134 cols wide,
# which fits the full 121-char status hint line without `@@@` truncation.
# Empirically: Width 1600 → 111 cols, 1800 → 125 cols, 2000 → 138 cols.
Set Width 2000
Set Height 540
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms
Set PlaybackSpeed 1.0

# Boot Neovim with the user's real config. `-c 'luafile ...'` injects the
# keypress overlay AFTER plugins load. Longer initial sleep because plugin
# managers like lazy need a beat to wake up.
Hide
Type "nvim -c 'luafile scripts/demo-overlay.lua'"
Enter
Sleep 2500ms
Type ":Rubikscube"
Enter
Sleep 1000ms
Show

# Brief solved beat.
Sleep 800ms

# Scramble.
Type "s"
Sleep 900ms

# A few manual moves — proves the cube is interactive.
Type "r"
Sleep 450ms
Type "U"
Sleep 450ms
Type "f"
Sleep 450ms
Type "L"
Sleep 650ms

# Auto-solve — the payoff. kociemba can return up to ~30 moves on hard
# scrambles; at 200ms/move that's 6s, plus the solver round-trip and the
# initial tempo delay. Budget 8s to ensure the animation completes before
# the rotation finale starts — otherwise the rotations cancel an in-flight
# animation and the cube ends partially solved.
Type "S"
Sleep 8s

# Brief beat on the solved frame before the verification rotations.
Sleep 700ms

# Rotation combo (y y x x) shows back/bottom faces — proves every side is
# uniformly colored. Then (x x y y) is the inverse, returning the cube to
# the original viewing orientation. (Rotations are self-inverse at 180°,
# so x²y²·x²y² = identity, restoring the initial state.)
Type "y"
Sleep 400ms
Type "y"
Sleep 400ms
Type "x"
Sleep 400ms
Type "x"
Sleep 600ms
Type "x"
Sleep 400ms
Type "x"
Sleep 400ms
Type "y"
Sleep 400ms
Type "y"
Sleep 800ms

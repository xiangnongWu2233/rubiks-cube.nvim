# Records a demo of the beginner tutorial feature using the user's REAL
# Neovim config (colorscheme, statusline, plugins).
#
# Storyboard:
#   open cube → scramble → t (tutorial panel) → `n` through the whole solve
#   at a constant pace, pausing 1s at every stage transition so the viewer
#   can read the new stage → "tutorial complete" payoff → y y victory spin.
#
# Determinism: a hidden `:lua` seeds math.random and sets scramble_length
# IMMEDIATELY before the `s` press (seeding at boot doesn't survive — config
# plugins consume random numbers during startup). With seed 42 and a 10-move
# scramble the tutorial solution is exactly 128 moves, split across stages
# as 2 / 16 / 27 / 29 / 10 / 1 / 17 / 26 (verified offline against
# lbl.solve) — the per-stage `n` counts below mirror that split exactly.
#
# Prerequisite: the loaded plugin must include the tutorial feature (lazy's
# clone at current main, or a `dir = <local checkout>` override in the spec).
#
# Run from the plugin root:
#     vhs scripts/record-tutorial-demo.tape
#
# Produces assets/tutorial-demo.gif + assets/tutorial-demo.mp4.

Output assets/tutorial-demo.gif
Output assets/tutorial-demo.mp4

Set FontSize 20
# Same canvas as record-demo.tape: at this height the cube float covers the
# startup dashboard entirely, giving the same clean background.
Set Width 2000
Set Height 540
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms
Set PlaybackSpeed 1.0

# Boot with the keypress overlay.
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

# Seed the RNG and lighten the scramble (hidden), then scramble on camera.
# The overlay offset parks the keypress box beside the tutorial panel
# instead of on top of it.
Hide
Type ":lua math.randomseed(42); require('rubikscube').setup({ scramble_length = 10 }); vim.g.demo_overlay_right_offset = 58"
Enter
Show
Type "s"
Sleep 1000ms

# Start the tutorial — panel pops up; give the viewer time to read stage 1.
Type "t"
Sleep 1800ms

# Stage 1: Hold the cube (2 moves), then pause on the new stage's panel.
Type@200ms "nn"
Sleep 1000ms
# Stage 2: White cross (16)
Type@200ms "nnnnnnnnnnnnnnnn"
Sleep 1000ms
# Stage 3: White corners (27)
Type@200ms "nnnnnnnnnnnnnnnnnnnnnnnnnnn"
Sleep 1000ms
# Stage 4: Middle layer (29)
Type@200ms "nnnnnnnnnnnnnnnnnnnnnnnnnnnnn"
Sleep 1000ms
# Stage 5: Yellow cross (10)
Type@200ms "nnnnnnnnnn"
Sleep 1000ms
# Stage 6: Yellow edges (1)
Type@200ms "n"
Sleep 1000ms
# Stage 7: Yellow corners (17)
Type@200ms "nnnnnnnnnnnnnnnnn"
Sleep 1000ms
# Stage 8: Twist corners (26) — ends the tutorial.
Type@200ms "nnnnnnnnnnnnnnnnnnnnnnnnnn"

# Solved: the panel closes on the finished solve.
Sleep 2000ms

# Slow victory spin.
Type@500ms "yy"
Sleep 1800ms

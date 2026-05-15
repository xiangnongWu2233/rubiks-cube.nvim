-- Drive a move sequence at configurable tempo, mutating the cube state and
-- firing per-step + completion callbacks. Built on vim.uv timers so it is
-- non-blocking and cancellable.

local cube = require("rubikscube.cube")

local M = {}

local uv = vim.uv or vim.loop

-- Start an animation. `opts`:
--   state    — the cube state to mutate (required)
--   moves    — list of cube.apply-compatible move tokens (required)
--   tempo_ms — ms between moves (default 200)
--   on_step  — fn(move, index) called after each move is applied
--   on_done  — fn() called after the last move
--   on_cancel — fn() called if the handle is cancelled mid-flight
-- Returns a handle table with :cancel() and :is_running().
function M.play(opts)
  assert(opts and opts.state and opts.moves, "animate.play: state and moves required")
  local tempo = opts.tempo_ms or 200
  local handle = { _running = true, _idx = 0 }
  local timer = uv.new_timer()

  local function cleanup()
    handle._running = false
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    timer = nil
  end

  function handle:is_running()
    return self._running
  end

  function handle:cancel()
    if not self._running then
      return
    end
    cleanup()
    if opts.on_cancel then
      pcall(opts.on_cancel)
    end
  end

  local function step()
    if not handle._running then
      return
    end
    handle._idx = handle._idx + 1
    local move = opts.moves[handle._idx]
    if not move then
      cleanup()
      if opts.on_done then
        pcall(opts.on_done)
      end
      return
    end
    local ok, err = pcall(cube.apply, opts.state, move)
    if not ok then
      cleanup()
      if opts.on_cancel then
        pcall(opts.on_cancel, err)
      end
      return
    end
    if opts.on_step then
      pcall(opts.on_step, move, handle._idx)
    end
  end

  -- If there are no moves, finish on the next tick so on_done is always
  -- delivered asynchronously (matches the success path semantics).
  if #opts.moves == 0 then
    timer:start(
      0,
      0,
      vim.schedule_wrap(function()
        cleanup()
        if opts.on_done then
          pcall(opts.on_done)
        end
      end)
    )
    return handle
  end

  -- First step fires after `tempo` ms so the viewer sees the starting state
  -- for a beat before the first move lands.
  timer:start(tempo, tempo, vim.schedule_wrap(step))
  return handle
end

return M

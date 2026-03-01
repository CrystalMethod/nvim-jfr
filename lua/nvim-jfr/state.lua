--- Shared session state for nvim-jfr.
--
-- Keeps small bits of state that multiple modules may need:
-- - last artifact path written (stop/dump)
-- - last output dir used
-- - current recording (pid/name/filename) started in this session

local M = {}

local state = {
  current_recording = nil,
  last_artifact = nil,
  last_output_dir = nil,
}

M.get_current_recording = function()
  return state.current_recording
end

M.set_current_recording = function(rec)
  state.current_recording = rec
end

M.get_last_artifact = function()
  return state.last_artifact
end

M.set_last_artifact = function(path)
  state.last_artifact = path
end

M.get_last_output_dir = function()
  return state.last_output_dir
end

M.set_last_output_dir = function(dir)
  state.last_output_dir = dir
end

return M

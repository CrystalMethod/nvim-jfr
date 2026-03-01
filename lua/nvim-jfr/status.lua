--- Status UI for nvim-jfr.
--
-- Provides :JFRStatus which shows active recordings for a JVM in a float.

local M = {}

local state = {
  buf = nil,
  win = nil,
  pid = nil,
  timer = nil,
  is_refreshing = false,
  last_refresh_ms = 0,
}

local function is_valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function is_valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function ensure_buf()
  if is_valid_buf(state.buf) then
    return state.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_name(buf, "nvim-jfr-status")
  state.buf = buf
  return buf
end

local function open_float(buf, enter)
  if is_valid_win(state.win) then
    -- Do not steal focus unless explicitly requested.
    if enter then
      pcall(vim.api.nvim_set_current_win, state.win)
    end
    return state.win
  end

  local columns = vim.o.columns
  local lines = vim.o.lines

  local width = math.min(90, math.max(60, math.floor(columns * 0.7)))
  local height = math.min(20, math.max(10, math.floor(lines * 0.5)))

  local row = math.floor((lines - height) / 2)
  local col = math.floor((columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, enter == true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " nvim-jfr status ",
    title_pos = "center",
  })

  state.win = win
  return win
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function render_loading(buf, pid)
  set_lines(buf, {
    string.format("# JFR Status (pid=%s)", tostring(pid or "?")),
    "",
    "Loading...",
    "",
    "- q: close",
    "- r: refresh",
  })
end

local function render_error(buf, pid, message)
  set_lines(buf, {
    string.format("# JFR Status (pid=%s)", tostring(pid or "?")),
    "",
    "## Error",
    "",
    tostring(message or "unknown error"),
    "",
    "- q: close",
    "- r: refresh",
  })
end

local function render_payload(buf, payload)
  local pid = payload and payload.pid or state.pid
  local recordings = payload and payload.recordings or nil
  local last_artifact = payload and payload.last_artifact or nil
  local out_dir = payload and payload.last_output_dir or nil

  local lines = {
    string.format("# JFR Status (pid=%s)", tostring(pid or "?")),
    "",
  }

  local utils = require("nvim-jfr.utils")
  table.insert(lines, "Updated: " .. utils.timestamp())
  table.insert(lines, "")

  if out_dir and out_dir ~= "" then
    table.insert(lines, "Output dir: `" .. tostring(out_dir) .. "`")
  end
  if last_artifact and last_artifact ~= "" then
    table.insert(lines, "Last artifact: `" .. tostring(last_artifact) .. "`")
  end
  if (out_dir and out_dir ~= "") or (last_artifact and last_artifact ~= "") then
    table.insert(lines, "")
  end

  if not recordings or #recordings == 0 then
    vim.list_extend(lines, {
      "No active recordings.",
      "",
      "Next: `:JFRStart` to start a recording.",
      "",
    })
  else
    table.insert(lines, string.format("Active recordings: %d", #recordings))
    table.insert(lines, "")
    for _, rec in ipairs(recordings) do
      local state_txt = rec.state and (" (" .. tostring(rec.state) .. ")") or ""
      local dur_txt = rec.duration and (", duration=" .. tostring(rec.duration)) or ""
      local file_txt = rec.filename or "<no filename>"
      table.insert(
        lines,
        string.format("- #%s: %s%s%s", tostring(rec.rec_num or "?"), tostring(file_txt), dur_txt, state_txt)
      )
    end
    table.insert(lines, "")
  end

  vim.list_extend(lines, {
    "- q: close",
    "- r: refresh",
    "- o: open recordings (:JFRRecordings)",
  })

  set_lines(buf, lines)
end

local function close()
  if state.timer then
    pcall(state.timer.stop, state.timer)
    pcall(state.timer.close, state.timer)
    state.timer = nil
  end
  if is_valid_win(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win = nil
  -- buffer is wiped by bufhidden=wipe when window closes
  state.buf = nil
  state.pid = nil
  state.is_refreshing = false
  state.last_refresh_ms = 0
end

local function set_keymaps(buf)
  local function map(lhs, rhs)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true })
  end
  map("q", close)
  map("<Esc>", close)
  map("r", function()
    if state.pid then
      M.refresh(state.pid)
    end
  end)
  map("o", function()
    pcall(vim.cmd, "JFRRecordings")
  end)
end

M.refresh = function(pid)
  -- Throttle and avoid overlapping refreshes.
  local uv = vim.uv or vim.loop
  local now = (uv and uv.now and uv.now()) or math.floor(os.time() * 1000)
  local cfg = require("nvim-jfr.config").get().status or {}
  local throttle = tonumber(cfg.refresh_throttle_ms or 0) or 0
  if state.is_refreshing then
    return
  end
  if throttle > 0 and state.last_refresh_ms > 0 and (now - state.last_refresh_ms) < throttle then
    return
  end

  state.is_refreshing = true
  state.last_refresh_ms = now

  state.pid = pid
  local buf = ensure_buf()
  -- Refresh should not unexpectedly steal focus from the user.
  open_float(buf, false)
  set_keymaps(buf)
  render_loading(buf, pid)

  require("nvim-jfr.status_query").query(pid, function(payload)
    -- If UI was closed while request was in-flight, bail.
    if not is_valid_buf(buf) then
      state.is_refreshing = false
      return
    end

    if not payload or not payload.ok then
      render_error(buf, pid, (payload and payload.error) or "unknown error")
      state.is_refreshing = false
      return
    end

    render_payload(buf, payload)
    state.is_refreshing = false
  end)
end

M.open = function(pid)
  if not pid then
    return
  end
  state.pid = pid
  local buf = ensure_buf()
  open_float(buf, true)
  M.refresh(pid)

  -- Optional periodic refresh while the window is open.
  local cfg = require("nvim-jfr.config").get().status or {}
  local enabled = cfg.auto_refresh == true
  local interval = tonumber(cfg.refresh_interval_ms or 0) or 0
  if enabled and interval > 0 then
    local uv = vim.uv or vim.loop
    if uv and uv.new_timer then
      if state.timer then
        pcall(state.timer.stop, state.timer)
        pcall(state.timer.close, state.timer)
        state.timer = nil
      end
      local t = uv.new_timer()
      state.timer = t
      t:start(interval, interval, function()
        vim.schedule(function()
          if state.pid and is_valid_win(state.win) then
            M.refresh(state.pid)
          else
            close()
          end
        end)
      end)
    end
  end
end

return M

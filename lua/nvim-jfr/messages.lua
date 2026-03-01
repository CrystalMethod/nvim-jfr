--- Canonical user-facing messages for commands.
--
-- Centralizes wording, next-step hints, and notification options.

local M = {}

local errors = require("nvim-jfr.errors")

M.title = "nvim-jfr"

local function pack(text, level, opts)
  opts = opts or {}
  if not opts.title then
    opts.title = M.title
  end
  return { text = tostring(text or ""), level = level or "info", opts = opts }
end

M.no_jvms = function()
  return pack("No running JVM processes found", "error", {
    dedupe = true,
    dedupe_key = "no_jvms",
    throttle_ms = 2000,
  })
end

M.start_ok = function(path, dropped, settings_value)
  local msg = "JFR started: " .. tostring(path)
  if settings_value and tostring(settings_value) ~= "" then
    msg = msg .. "\nSettings: " .. tostring(settings_value)
  end
  if dropped and #dropped > 0 then
    msg = msg .. "\nIgnored unsupported options: " .. table.concat(dropped, ", ")
    return pack(msg .. "\nNext: :JFRStatus, :JFRStop", "warn")
  end
  return pack(msg .. "\nNext: :JFRStatus, :JFRStop", "info")
end

M.start_err = function(res)
  return pack(errors.format_jcmd_error("Failed to start JFR", res), "error")
end

M.settings_resolve_failed = function(err)
  return pack(tostring(err or "Failed to resolve settings"), "error")
end

M.settings_not_supported = function(err)
  return pack(tostring(err or "settings not supported"), "error")
end

M.start_overrides_rejected = function(keys)
  keys = keys or {}
  if #keys == 0 then
    return nil
  end
  return pack("Ignored unsupported overrides: " .. table.concat(keys, ", "), "warn")
end

M.jfr_check_failed = function(res)
  return pack(errors.format_jcmd_error("JFR.check failed", res), "error")
end

M.stop_ok_one = function(path)
  return pack("JFR stopped: " .. tostring(path) .. "\nNext: :JFRRecordings", "info")
end

M.stop_ok_many = function(n)
  return pack("JFR stopped " .. tostring(n) .. " recording(s)", "info")
end

M.stop_err = function(summary)
  return pack(tostring(summary or "Failed to stop recording"), "error")
end

M.dump_ok_one = function(path)
  return pack("JFR dumped to: " .. tostring(path) .. "\nNext: :JFRRecordings", "info")
end

M.dump_ok_many = function(n, out_dir)
  return pack("JFR dumped " .. tostring(n) .. " recording(s) to: " .. tostring(out_dir), "info")
end

M.dump_err = function(summary)
  return pack(tostring(summary or "Failed to dump recording"), "error")
end

M.check_no_recordings = function(pid)
  return pack("No active recordings on JVM " .. tostring(pid) .. ". Try :JFRStart.", "info")
end

M.capabilities_detect_failed = function(pid)
  return pack("Failed to detect capabilities for JVM " .. tostring(pid), "error")
end

M.opening_jmc = function(path)
  return pack("Opening " .. tostring(path) .. " in JMC", "info")
end

M.opening_default = function(path)
  return pack("Opening " .. tostring(path), "info")
end

M.open_failed = function(text)
  return pack(tostring(text or "Failed to open"), "error")
end

M.jfc_templates_none = function()
  return pack(
    table.concat({
      "No JFC templates found.",
      "",
      "Configure `jfc_templates.project_dirs`.",
      "Example:",
      "  require('nvim-jfr').setup({ jfc_templates = { project_dirs = { '.jfr/templates' } } })",
    }, "\n"),
    "warn",
    { dedupe = true, dedupe_key = "jfc_templates_none", throttle_ms = 3000 }
  )
end

M.open_dir_failed = function(text)
  return pack(tostring(text or "Could not open output directory automatically"), "warn")
end

M.open_output_dir_failed = function(out_dir, err)
  local msg = "Could not open output directory automatically"
  if err ~= nil then
    msg = msg .. ": " .. tostring(err)
  end
  if out_dir ~= nil then
    msg = msg .. "\nPath: " .. tostring(out_dir)
  end
  return pack(msg, "warn")
end

M.open_file_not_found = function(path)
  return pack("JFR file not found: " .. tostring(path), "error")
end

M.open_jmc_exit = function(code)
  return pack("Failed to open JMC (exit code: " .. tostring(code) .. ")", "error")
end

M.open_no_jmc_and_system_open_failed = function(jmc_command, err, path)
  local msg = "JMC not found (jmc_command=" .. tostring(jmc_command) .. ")"
  msg = msg .. " and system open failed: " .. tostring(err)
  msg = msg .. "\nFile: " .. tostring(path)
  return pack(msg, "error")
end

M.out_dir_prepare_failed = function(err)
  return pack(tostring(err or "failed to prepare output directory"), "error")
end

M.output_path_prepare_failed = function(err)
  return pack(tostring(err or "failed to prepare output path"), "error")
end

M.recordings_none = function(out_dir)
  return pack("No recordings found in: " .. tostring(out_dir), "info")
end

M.recordings_deleted = function(n)
  return pack("Deleted " .. tostring(n) .. " recording(s)", "info")
end

M.recordings_delete_errors = function(errs)
  return pack("Delete errors: " .. tostring(errs or "unknown error"), "error")
end

return M

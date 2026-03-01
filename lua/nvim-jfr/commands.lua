--- Commands module - implements the user-facing :JFR* commands
--- @module nvim-jfr.commands

local M = {}

local state = require("nvim-jfr.state")

-- Enrich JVM entries for pickers (best-effort, cached).
-- This keeps picker rendering simple and avoids running expensive lookups
-- in the picker backends.
local function enrich_jvm_items(jvms)
  local jvm_mod = require("nvim-jfr.jvm")
  local cfg = require("nvim-jfr.config").get()

  -- Default: avoid blocking the picker on per-PID `jcmd <pid> VM.version`.
  -- Users can opt in if they really want the extra info.
  if cfg and cfg.show_java_version_in_picker ~= true then
    return jvms
  end

  for _, j in ipairs(jvms or {}) do
    if type(j) == "table" and j.pid and j.java_version == nil then
      -- Cached + short timeout; keep picker UX snappy.
      j.java_version = jvm_mod.get_java_version(j.pid)
    end
  end
  return jvms
end

local function filter_tooling_jvms(jvms)
  local config = require("nvim-jfr.config").get()
  local probe = config.project_jvm_probe or {}
  local patterns = probe.exclude_raw_patterns
  if type(patterns) ~= "table" or #patterns == 0 then
    return jvms
  end
  return require("nvim-jfr.jvm").filter_excluded(jvms, patterns)
end

local function notify_msg(msg)
  local utils = require("nvim-jfr.utils")
  if not msg then
    return
  end
  utils.notify(msg.text or msg[1] or "", msg.level or msg[2] or "info", msg.opts)
end

local function safe_iso8601_utc()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function write_recording_meta(recording_path, meta)
  local ok_meta, meta_mod = pcall(require, "nvim-jfr.recording_meta")
  if not ok_meta or not meta_mod then
    return
  end
  -- Best-effort: never block stop/dump.
  pcall(function()
    meta_mod.write_for_recording(recording_path, meta)
  end)
end

--- Create a new project-local .jfc from a selected template.
---
--- Default destination: <project-root>/.jfr/templates/<template-name>
---
--- Asks for filename, and prompts before overwrite.
M.jfc_new_from_template = function()
  local config = require("nvim-jfr.config").get()
  local templates = require("nvim-jfr.jfc_templates").list(config)
  local messages = require("nvim-jfr.messages")
  local utils = require("nvim-jfr.utils")
  local platform = require("nvim-jfr.platform")
  local proj = require("nvim-jfr.project")

  if not templates or #templates == 0 then
    notify_msg(messages.jfc_templates_none())
    return
  end

  local root = proj.get_root(0)
  if not root or root == "" then
    utils.notify("No project root detected; cannot create project-local JFC. Open a project or :cd into it.", "error")
    return
  end

  require("nvim-jfr.picker").pick(templates, {
    title = "Select JFC template to copy",
    picker = config.picker,
    multi = false,
    preview = false,
    on_confirm = function(selected)
      local item = selected
      if selected and selected[1] then
        item = selected[1]
      end
      if not item or not item.path or not item.name then
        return
      end

      local default_dir = platform.join_path(root, ".jfr", "templates")
      local default_name = item.name
      local input = vim.fn.input({
        prompt = "New JFC filename (under .jfr/templates): ",
        default = default_name,
      })
      local fname = vim.trim(tostring(input or ""))
      if fname == "" then
        return
      end
      if fname:lower():sub(-4) ~= ".jfc" then
        fname = fname .. ".jfc"
      end

      local dest = platform.normalize_path(platform.join_path(default_dir, fname))
      local exists = (vim.uv or vim.loop).fs_stat(dest)
      if exists and exists.type == "file" then
        local ok = vim.fn.confirm("Overwrite existing file?\n" .. dest, "&Yes\n&No", 2)
        if ok ~= 1 then
          return
        end
      end

      local jfc = require("nvim-jfr.jfc")
      local ok_copy, err_copy = jfc.copy_template(item.path, dest, { overwrite = true })
      if not ok_copy then
        utils.notify("Failed to create JFC: " .. tostring(err_copy), "error")
        return
      end

      vim.cmd("edit " .. vim.fn.fnameescape(dest))
      utils.notify("Created JFC: " .. dest, "info")
    end,
  })
end

--- Parse command line arguments
---@param args table Command arguments
---@return table Parsed options
M.parse_args = function(args)
  local opts = {}
  for _, arg in ipairs(args) do
    local key, value = arg:match("^%-%-([%w_-]+)=(.+)$")
    if key then
      opts[key] = value
    end
  end
  return opts
end

--- Extract per-recording JFR.start option overrides from CLI args.
---
--- Supports two styles:
---  1) direct unknown flags: `:JFRStart --maxage=10m --maxsize=250M`
---  2) explicit opt wrapper: `:JFRStart --opt=maxage=10m`
---
--- Reserved args (handled elsewhere) are not treated as overrides.
---
--- @param args table string[]
--- @return table overrides key->value
M.parse_start_overrides = function(args)
  args = args or {}

  local reserved = {
    duration = true,
    name = true,
    filename = true,
    settings = true,
    -- Reserved for future named run configurations. Must never be forwarded
    -- to jcmd as a JFR.start option.
    run = true,
    opt = true,
  }

  local overrides = {}

  -- Wrapper style: --opt=key=value
  for _, arg in ipairs(args) do
    local kv = arg:match("^%-%-opt=(.+)$")
    if kv then
      local k, v = kv:match("^([^=]+)=(.+)$")
      k = k and vim.trim(k) or nil
      if k and k ~= "" and v ~= nil then
        overrides[k] = v
      end
    end
  end

  -- Direct style: unknown `--key=value` are treated as start overrides.
  local parsed = M.parse_args(args)
  for k, v in pairs(parsed) do
    if not reserved[k] then
      overrides[k] = v
    end
  end

  return overrides
end

local function keys_list(t)
  local out = {}
  for k, v in pairs(t or {}) do
    if v then
      table.insert(out, k)
    end
  end
  table.sort(out)
  return out
end

--- Show status for active recordings (float UI)
M.status = function()
  local jvm_mod = require("nvim-jfr.jvm")
  local config = require("nvim-jfr.config").get()
  local project = require("nvim-jfr.project")
  local messages = require("nvim-jfr.messages")

  local root = project.get_root(0)
  local probe = config.project_jvm_probe or {}
  local jvms = config.project_scoped_jvms and root and jvm_mod.list_for_project(root, {
    probe_system_properties = probe.enabled,
    timeout_ms = probe.timeout_ms,
    max_probes = probe.max_probes,
    time_budget_ms = probe.time_budget_ms,
    stop_after_first_match = probe.stop_after_first_match,
    exclude_raw_patterns = probe.exclude_raw_patterns,
  }) or jvm_mod.list()
  if (#jvms == 0) and config.project_scoped_jvms and root then
    jvms = jvm_mod.list()
  end
  jvms = filter_tooling_jvms(jvms)
  if #jvms == 0 then
    notify_msg(messages.no_jvms())
    return
  end

  require("nvim-jfr.picker").pick(enrich_jvm_items(jvms), {
    title = "Select JVM for status",
    picker = config.picker,
    multi = false,
    preview = false,
    on_confirm = function(selected_jvm)
      local jvm = selected_jvm
      if selected_jvm and selected_jvm[1] then
        jvm = selected_jvm[1]
      end
      if not jvm or not jvm.pid then
        return
      end
      require("nvim-jfr.status").open(jvm.pid)
    end,
  })
end

--- Start a JFR recording
M.start = function(args)
  local jvm = require("nvim-jfr.jvm")
  local jfr = require("nvim-jfr.jfr")
  local config = require("nvim-jfr.config").get()
  local utils = require("nvim-jfr.utils")
  local errors = require("nvim-jfr.errors")
  local project = require("nvim-jfr.project")
  local messages = require("nvim-jfr.messages")

  -- List JVMs and let user pick
  local root = project.get_root(0)
  local probe = config.project_jvm_probe or {}
  local jvms = config.project_scoped_jvms and root and jvm.list_for_project(root, {
    probe_system_properties = probe.enabled,
    timeout_ms = probe.timeout_ms,
    max_probes = probe.max_probes,
    time_budget_ms = probe.time_budget_ms,
    stop_after_first_match = probe.stop_after_first_match,
    exclude_raw_patterns = probe.exclude_raw_patterns,
  }) or jvm.list()
  if (#jvms == 0) and config.project_scoped_jvms and root then
    -- Fallback to global list if scoped list yields none.
    jvms = jvm.list()
  end
  jvms = filter_tooling_jvms(jvms)

  if #jvms == 0 then
    notify_msg(messages.no_jvms())
    return
  end

  require("nvim-jfr.picker").pick(enrich_jvm_items(jvms), {
    title = "Select JVM to record",
    picker = config.picker,
    multi = false,
    preview = false,
    on_confirm = function(selected_jvm)
      -- Handle single item (vim picker) or table (snacks picker)
      local jvm = selected_jvm
      if selected_jvm and selected_jvm[1] then
        jvm = selected_jvm[1]
      end
      if not jvm or not jvm.pid then
        return
      end

      local opts = M.parse_args(args)
      local cli_overrides = M.parse_start_overrides(args)

      local root = project.get_root(0)

      -- Run config selection (project-only). For now, only the opt-out
      -- sentinel is guaranteed to work even without a run-configs file.
      local run_name = opts.run
      if run_name and vim.trim(tostring(run_name)) == "" then
        run_name = nil
      end
      if run_name then
        run_name = vim.trim(tostring(run_name))
      end

      local run_cfg = nil
      local run_cfg_name = nil
      local function run_is_none()
        return run_name and run_name:lower() == "none"
      end

      local run_mod = require("nvim-jfr.run_configs")
      local function apply_run_cfg_and_start()
        local settings_mod = require("nvim-jfr.settings")

        local run_duration = run_cfg and run_cfg.duration or nil
        local run_settings = run_cfg and run_cfg.settings or nil

        -- Resolve settings using precedence:
        -- CLI (--settings) > run config settings > plugin config.settings
        local resolved_run_settings
        if run_settings ~= nil then
          local rr, rerr = run_mod.resolve_run_settings(root, run_settings)
          if rerr then
            utils.notify("Run config '" .. tostring(run_cfg_name) .. "' settings error: " .. tostring(rerr), "error")
            return
          end
          resolved_run_settings = rr
        end

        local resolved_settings, settings_err = settings_mod.resolve({
          settings_value = opts.settings or resolved_run_settings,
          configured_settings_value = config.settings,
        })
        if settings_err then
          notify_msg(messages.settings_resolve_failed(settings_err))
          return
        end

        local recording_opts = {
          pid = jvm.pid,
          name = opts.name or "recording",
          duration = opts.duration or run_duration or config.default_duration,
          filename = opts.filename or utils.generate_filename(jvm.pid),
          settings = resolved_settings,
        }

        -- Resolve output directory + ensure it exists.
        local rec_mod = require("nvim-jfr.recordings")
        local out_dir = rec_mod.get_output_dir(config)
        local ok_dir, err_dir = rec_mod.ensure_output_dir(out_dir)
        if not ok_dir then
          notify_msg(messages.out_dir_prepare_failed(err_dir))
          return
        end
        recording_opts.filename = rec_mod.resolve_output_path(recording_opts.filename, out_dir)
        local ok_parent, err_parent = rec_mod.ensure_parent_dir(recording_opts.filename)
        if not ok_parent then
          notify_msg(messages.output_path_prepare_failed(err_parent))
          return
        end

        local function do_start(cap)
          local ok_supported, err_supported = settings_mod.validate_supported(resolved_settings, cap)
          if not ok_supported then
            notify_msg(messages.settings_not_supported(err_supported))
            return
          end

          -- Apply per-recording start overrides (config + run config + CLI), capability-gated.
          local overrides_mod = require("nvim-jfr.overrides")
          local supported = cap and cap.jfr and cap.jfr.start_options or nil
          if type(supported) == "table" and next(supported) == nil then
            supported = nil
          end

          local base_start_opts = {
            name = recording_opts.name,
            duration = recording_opts.duration,
            filename = recording_opts.filename,
            settings = recording_opts.settings,
          }

          local rejected_all = {}
          local merged = base_start_opts

          if config.start_overrides and type(config.start_overrides) == "table" and next(config.start_overrides) ~= nil then
            local rej
            merged, _, rej = overrides_mod.apply(merged, config.start_overrides, supported)
            vim.list_extend(rejected_all, rej or {})
          end

          if run_cfg and type(run_cfg.start_overrides) == "table" and next(run_cfg.start_overrides) ~= nil then
            local rej
            merged, _, rej = overrides_mod.apply(merged, run_cfg.start_overrides, supported)
            vim.list_extend(rejected_all, rej or {})
          end

          if cli_overrides and type(cli_overrides) == "table" and next(cli_overrides) ~= nil then
            local rej
            merged, _, rej = overrides_mod.apply(merged, cli_overrides, supported)
            vim.list_extend(rejected_all, rej or {})
          end

          if #rejected_all > 0 then
            local uniq = {}
            for _, k in ipairs(rejected_all) do
              uniq[k] = true
            end
            rejected_all = {}
            for k, v in pairs(uniq) do
              if v then
                table.insert(rejected_all, k)
              end
            end
            table.sort(rejected_all)
          end

          if (config.start_overrides and next(config.start_overrides or {}) ~= nil)
            or (run_cfg and next(run_cfg.start_overrides or {}) ~= nil)
            or (cli_overrides and next(cli_overrides or {}) ~= nil)
          then
            recording_opts._start_overrides_rejected = rejected_all
            recording_opts._start_opts_override = merged
          end

          jfr.start(recording_opts, function(res)
            if res and res.ok then
              local current_recording = {
                pid = jvm.pid,
                name = recording_opts.name,
                filename = recording_opts.filename,
                run_config_name = run_cfg_name,
                jfr_start = {
                  duration = recording_opts.duration,
                  settings = resolved_settings,
                  start_overrides = merged,
                  start_overrides_rejected = recording_opts._start_overrides_rejected,
                },
              }
              state.set_current_recording(current_recording)
              notify_msg(messages.start_ok(recording_opts.filename, res.dropped_options, resolved_settings))
              notify_msg(messages.start_overrides_rejected(recording_opts._start_overrides_rejected))
            else
              notify_msg(messages.start_err(res))
            end
          end)
        end

        local ok_caps, caps = pcall(require, "nvim-jfr.capabilities")
        if ok_caps and caps then
          caps.detect(jvm.pid, function(cap)
            do_start(cap)
          end)
        else
          do_start(nil)
        end
      end

      if run_is_none() then
        apply_run_cfg_and_start()
        return
      end

      -- If user specified a run config name, try to load it.
      if run_name then
        if not root or root == "" then
          utils.notify("No project root detected; cannot use named run configs", "error")
          return
        end
        local cfg, err = run_mod.get(root, run_name)
        if err then
          utils.notify(tostring(err), "error")
          return
        end
        run_cfg = cfg
        run_cfg_name = run_name
        apply_run_cfg_and_start()
        return
      end

      -- Otherwise, if a run config file exists with configs, prompt.
      if root and root ~= "" then
          local items, list_err = run_mod.list(root)
          if items and #items > 0 then
            -- Put default first (best-effort) so all pickers behave similarly.
            local default_name = run_mod.get_default_name(root)
            if default_name then
              table.sort(items, function(a, b)
                if a.name == default_name then
                  return true
                end
                if b.name == default_name then
                  return false
                end
                return tostring(a.name) < tostring(b.name)
              end)
            end

            require("nvim-jfr.picker").pick(items, {
              title = "Select run config",
              picker = config.picker,
              multi = false,
              preview = false,
              on_confirm = function(selected)
                local item = selected
                if selected and selected[1] then
                  item = selected[1]
                end
              if not item or not item.name then
                return
              end
              run_cfg = item.config
              run_cfg_name = item.name
              apply_run_cfg_and_start()
            end,
          })
          return
        elseif list_err then
          -- Only surface loader errors when the file exists but is invalid.
          -- (Missing file should behave like current behavior.)
          local p = run_mod.file_path(root)
          if p and vim.fn.filereadable(p) == 1 then
            utils.notify(tostring(list_err), "error")
            return
          end
        end
      end

      -- No run configs: behave like current behavior.
      apply_run_cfg_and_start()
      return
      end,
    })
 end

--- Stop a JFR recording
---
--- Options:
---   --filename=...  base output filename hint (optional)
---   --all=true      stop all recordings for selected JVM (with confirmation)
---
--- Suffix modifiers:
---   :JFRStop!       stop all recordings for selected JVM (no confirmation)
M.stop = function(args, cmdopts)
  local jfr = require("nvim-jfr.jfr")
  local utils = require("nvim-jfr.utils")
  local errors = require("nvim-jfr.errors")
  local jvm_mod = require("nvim-jfr.jvm")
  local config = require("nvim-jfr.config").get()
  local project = require("nvim-jfr.project")
  local rec_mod = require("nvim-jfr.recordings")
  local messages = require("nvim-jfr.messages")

  local opts = M.parse_args(args)

  local function parse_all(a)
    local o = M.parse_args(a or {})
    return (o.all == "true" or o.all == "1")
  end

  local stop_all = parse_all(args) or (cmdopts and cmdopts.bang == true)

  -- Ensure output dir exists so we can always dump to a file.
  local out_dir = rec_mod.get_output_dir(config)
  state.set_last_output_dir(out_dir)
  local ok_dir, err_dir = rec_mod.ensure_output_dir(out_dir)
  if not ok_dir then
    notify_msg(messages.out_dir_prepare_failed(err_dir))
    return
  end

  local function resolve_stop_filename(pid, hint, suffix)
    pid = tonumber(pid)
    local name = hint

    -- When stopping multiple recordings, avoid collisions.
    if suffix and suffix ~= "" then
      if name and name ~= "" then
        if name:sub(-4) == ".jfr" then
          name = name:sub(1, -5) .. "_" .. suffix .. ".jfr"
        else
          name = name .. "_" .. suffix .. ".jfr"
        end
      else
        local ts = os.date("%Y%m%d_%H%M%S")
        name = string.format("recording_%d_%s_rec%s.jfr", pid or 0, ts, suffix)
      end
    end

    name = name or utils.generate_filename(pid)
    local path = rec_mod.resolve_output_path(name, out_dir)
    local ok_parent, err_parent = rec_mod.ensure_parent_dir(path)
    if not ok_parent then
      return nil, err_parent
    end
    return path, nil
  end

  --- Stop recording(s) for given pid.
  ---@param pid number|string
  ---@param hooks? table { on_no_recordings?: fun(pid:number) }
  local function stop_recordings_for_pid(pid, hooks)
    pid = tonumber(pid)
    if not pid then
      return false
    end

    jfr.check(pid, function(res)
      if not res or not res.ok then
        notify_msg(messages.jfr_check_failed(res))
        return
      end

      local recordings = jfr.parse_recordings(res.stdout or "")
      if #recordings == 0 then
        notify_msg(messages.check_no_recordings(pid))
        if hooks and type(hooks.on_no_recordings) == "function" then
          hooks.on_no_recordings(pid)
        end
        return
      end

      local function do_stop_many(selected)
        -- Stop sequentially to avoid jcmd attach contention.
        local results = { ok = {}, err = {} }
        local idx = 1

        local function stop_next()
          local rec = selected[idx]
            if not rec then
              if #results.err == 0 then
                if #results.ok == 1 then
                  state.set_last_artifact(results.ok[1])
                  write_recording_meta(results.ok[1], {
                    created_at = safe_iso8601_utc(),
                    action = "stop",
                    run_config_name = (state.get_current_recording() or {}).run_config_name,
                    jvm = {
                      pid = pid,
                      java_version = require("nvim-jfr.jvm").get_java_version(pid),
                    },
                    jfr_start = (state.get_current_recording() or {}).jfr_start,
                  })
                  notify_msg(messages.stop_ok_one(results.ok[1]))
                else
                  state.set_last_artifact(results.ok[#results.ok])
                  write_recording_meta(results.ok[#results.ok], {
                    created_at = safe_iso8601_utc(),
                    action = "stop",
                    run_config_name = (state.get_current_recording() or {}).run_config_name,
                    jvm = {
                      pid = pid,
                      java_version = require("nvim-jfr.jvm").get_java_version(pid),
                    },
                    jfr_start = (state.get_current_recording() or {}).jfr_start,
                  })
                  notify_msg(messages.stop_ok_many(#results.ok))
                end
              else
                local msg = string.format(
                  "Stopped %d recording(s), failed %d: %s",
                  #results.ok,
                  #results.err,
                  table.concat(results.err, "; ")
                )
                notify_msg(messages.stop_err(msg))
              end
              return
            end

          local rec_num = tostring(rec.rec_num or "")
          local save_path, save_err = resolve_stop_filename(pid, opts.filename or rec.filename, rec_num)
          if not save_path then
            table.insert(
              results.err,
              (rec.filename or ("Recording " .. tostring(rec_num))) .. ": " .. (save_err or "failed to prepare output path")
            )
            idx = idx + 1
            stop_next()
            return
          end

          jfr.stop({
            pid = pid,
            -- Prefer recording number; this is the most reliable identifier across JDKs.
            name = tostring(rec.rec_num),
            filename = save_path,
          }, function(stop_res)
            if stop_res and stop_res.ok then
              table.insert(results.ok, save_path)
              write_recording_meta(save_path, {
                created_at = safe_iso8601_utc(),
                action = "stop",
                run_config_name = (state.get_current_recording() or {}).run_config_name,
                jvm = {
                  pid = pid,
                  java_version = require("nvim-jfr.jvm").get_java_version(pid),
                },
                jfr_start = (state.get_current_recording() or {}).jfr_start,
                jfr_check = {
                  rec_num = rec.rec_num,
                  filename = rec.filename,
                  duration = rec.duration,
                  state = rec.state,
                },
              })
            else
              local emsg = errors.format_jcmd_error("Failed", stop_res):gsub("\n", " ")
              table.insert(results.err, save_path .. ": " .. emsg)
            end
            idx = idx + 1
            stop_next()
          end)
        end

        stop_next()
      end

      if stop_all then
        if #recordings == 1 then
          do_stop_many({ recordings[1] })
          return
        end

        -- :JFRStop! skips confirmation, :JFRStop --all=true confirms.
        if not (cmdopts and cmdopts.bang == true) then
          local ok = vim.fn.confirm(
            string.format("Stop ALL %d recordings for PID %d?", #recordings, pid),
            "&Yes\n&No",
            2
          )
          if ok ~= 1 then
            return
          end
        end

        do_stop_many(recordings)
        return
      end

      -- Default: always pick when multiple recordings are present.
      -- If only one recording exists, stop it directly.
      if #recordings == 1 then
        do_stop_many({ recordings[1] })
        return
      end

      require("nvim-jfr.picker").pick(recordings, {
        title = "Select recording(s) to stop (Tab to multi-select)",
        picker = config.picker,
        multi = true,
        preview = false,
        on_confirm = function(selected_recordings)
          local selected = selected_recordings
          if selected_recordings and selected_recordings.rec_num then
            selected = { selected_recordings }
          end
          if not selected or #selected == 0 then
            return
          end
          do_stop_many(selected)
        end,
      })
    end)
    return true
  end

  local function pick_jvm_to_stop()
    local root = project.get_root(0)
    local probe = config.project_jvm_probe or {}
    local jvms = config.project_scoped_jvms and root and jvm_mod.list_for_project(root, {
      probe_system_properties = probe.enabled,
      timeout_ms = probe.timeout_ms,
      max_probes = probe.max_probes,
      time_budget_ms = probe.time_budget_ms,
      stop_after_first_match = probe.stop_after_first_match,
      exclude_raw_patterns = probe.exclude_raw_patterns,
    }) or jvm_mod.list()
    if (#jvms == 0) and config.project_scoped_jvms and root then
      jvms = jvm_mod.list()
    end
    jvms = filter_tooling_jvms(jvms)
    if #jvms == 0 then
      notify_msg(messages.no_jvms())
      return
    end

    require("nvim-jfr.picker").pick(enrich_jvm_items(jvms), {
      title = "Select JVM to stop recording",
      picker = config.picker,
      multi = false,
      preview = false,
      on_confirm = function(selected_jvm)
        local jvm = selected_jvm
        if selected_jvm and selected_jvm[1] then
          jvm = selected_jvm[1]
        end
        if not jvm or not jvm.pid then
          return
        end
        stop_recordings_for_pid(jvm.pid)
      end,
    })
  end

  -- Convenience: if we started a recording in this session, try that JVM first.
  local current_recording = state.get_current_recording()
  if current_recording and current_recording.pid then
    if stop_recordings_for_pid(current_recording.pid, {
      on_no_recordings = function()
        pick_jvm_to_stop()
      end,
    }) then
      return
    end
  end

  -- Otherwise, let user pick a JVM.
  pick_jvm_to_stop()
end

--- Dump a JFR recording
---
--- Options:
---   --filename=...  output filename hint (optional)
---   --pick=true     always pick recording(s) (even if there is only one)
---
--- Suffix modifiers:
---   :JFRDump!       always pick recording(s) (even if there is only one)
M.dump = function(args, cmdopts)
  local jfr = require("nvim-jfr.jfr")
  local utils = require("nvim-jfr.utils")
  local errors = require("nvim-jfr.errors")
  local jvm_mod = require("nvim-jfr.jvm")
  local config = require("nvim-jfr.config").get()
  local project = require("nvim-jfr.project")
  local platform = require("nvim-jfr.platform")
  local messages = require("nvim-jfr.messages")

  local opts = M.parse_args(args)

  local function parse_pick(a)
    local o = M.parse_args(a or {})
    return (o.pick == "true" or o.pick == "1")
  end

  local always_pick = parse_pick(args) or (cmdopts and cmdopts.bang == true)

  local rec_mod = require("nvim-jfr.recordings")
  local out_dir = rec_mod.get_output_dir(config)
  state.set_last_output_dir(out_dir)
  local ok_dir, err_dir = rec_mod.ensure_output_dir(out_dir)
  if not ok_dir then
    notify_msg(messages.out_dir_prepare_failed(err_dir))
    return
  end

  local function ensure_unique_path(path)
    if vim.fn.filereadable(path) ~= 1 then
      return path
    end
    local dir = vim.fn.fnamemodify(path, ":h")
    local base = vim.fn.fnamemodify(path, ":t:r")
    local ext = vim.fn.fnamemodify(path, ":e")
    if ext == "" then
      ext = "jfr"
    end
    for i = 1, 999 do
      local candidate = platform.join_path(dir, string.format("%s_%d.%s", base, i, ext))
      if vim.fn.filereadable(candidate) ~= 1 then
        return candidate
      end
    end
    -- last resort: timestamp
    local ts = os.date("%Y%m%d_%H%M%S")
    return platform.join_path(dir, string.format("%s_%s.%s", base, ts, ext))
  end

  local function resolve_dump_filename(pid, hint, suffix)
    pid = tonumber(pid)
    local name = hint

    -- When dumping multiple recordings, avoid collisions by suffixing.
    if suffix and suffix ~= "" then
      if name and name ~= "" then
        if name:sub(-4) == ".jfr" then
          name = name:sub(1, -5) .. "_" .. suffix .. ".jfr"
        else
          name = name .. "_" .. suffix .. ".jfr"
        end
      else
        local ts = os.date("%Y%m%d_%H%M%S")
        name = string.format("dump_%d_%s_rec%s.jfr", pid or 0, ts, suffix)
      end
    end

    name = name or utils.generate_filename(pid)
    local path = rec_mod.resolve_output_path(name, out_dir)
    local ok_parent, err_parent = rec_mod.ensure_parent_dir(path)
    if not ok_parent then
      return nil, err_parent
    end
    return path, nil
  end

  --- Sort recordings so the most recent (highest rec_num) is first.
  local function sort_recordings_latest_first(recs)
    table.sort(recs, function(a, b)
      return (tonumber(a.rec_num) or 0) > (tonumber(b.rec_num) or 0)
    end)
    return recs
  end

  --- Dump recording(s) for a given pid.
  local function dump_recordings_for_pid(pid, hooks)
    pid = tonumber(pid)
    if not pid then
      return false
    end

    hooks = hooks or {}

    -- Dump requires a specific recording when multiple are running.
    jfr.check(pid, function(check_res)
        if not check_res or not check_res.ok then
          notify_msg(messages.jfr_check_failed(check_res))
          return
        end

        local recordings = jfr.parse_recordings(check_res.stdout or "")
        sort_recordings_latest_first(recordings)

        if #recordings == 0 then
          notify_msg(messages.check_no_recordings(pid))
          if type(hooks.on_no_recordings) == "function" then
            hooks.on_no_recordings(pid)
          end
          return
        end

        local function do_dump_many(selected)
          -- Dump sequentially to avoid jcmd attach contention.
          local results = { ok = {}, err = {} }
          local idx = 1
          local multi = #selected > 1

          local function dump_next()
            local rec = selected[idx]
            if not rec then
              if #results.err == 0 then
                if #results.ok >= 1 then
                  state.set_last_artifact(results.ok[#results.ok])
                  write_recording_meta(results.ok[#results.ok], {
                    created_at = safe_iso8601_utc(),
                    action = "dump",
                    run_config_name = (state.get_current_recording() or {}).run_config_name,
                    jvm = {
                      pid = pid,
                      java_version = require("nvim-jfr.jvm").get_java_version(pid),
                    },
                    jfr_start = (state.get_current_recording() or {}).jfr_start,
                  })
                end
                if #results.ok == 1 then
                  local p = results.ok[1]
                  notify_msg(messages.dump_ok_one(p))
                else
                  notify_msg(messages.dump_ok_many(#results.ok, out_dir))
                end
              else
                local msg = string.format(
                  "Dumped %d recording(s), failed %d: %s",
                  #results.ok,
                  #results.err,
                  table.concat(results.err, "; ")
                )
                notify_msg(messages.dump_err(msg))
              end
              return
            end

            local rec_num = tostring(rec.rec_num or "")
            local suffix = multi and rec_num or nil
            local hint = opts.filename or rec.filename
            local save_path, save_err = resolve_dump_filename(pid, hint, suffix)
            if not save_path then
              table.insert(
                results.err,
                (rec.filename or ("Recording " .. tostring(rec_num)))
                  .. ": "
                  .. (save_err or "failed to prepare output path")
              )
              idx = idx + 1
              dump_next()
              return
            end

            -- Existing file behavior:
            -- - For multi dumps: always auto-unique.
            -- - For single dump: confirm overwrite, else auto-unique.
            if vim.fn.filereadable(save_path) == 1 then
              if multi then
                save_path = ensure_unique_path(save_path)
              else
                local ok = vim.fn.confirm(
                  "File exists:\n" .. save_path .. "\n\nOverwrite?",
                  "&Yes\n&No",
                  2
                )
                if ok ~= 1 then
                  save_path = ensure_unique_path(save_path)
                end
              end
            end

            jfr.dump({
              pid = pid,
              name = tostring(rec.rec_num),
              filename = save_path,
            }, function(dump_res)
              if dump_res and dump_res.ok then
                table.insert(results.ok, save_path)
                write_recording_meta(save_path, {
                  created_at = safe_iso8601_utc(),
                  action = "dump",
                  run_config_name = (state.get_current_recording() or {}).run_config_name,
                  jvm = {
                    pid = pid,
                    java_version = require("nvim-jfr.jvm").get_java_version(pid),
                  },
                  jfr_start = (state.get_current_recording() or {}).jfr_start,
                  jfr_check = {
                    rec_num = rec.rec_num,
                    filename = rec.filename,
                    duration = rec.duration,
                    state = rec.state,
                  },
                })
              else
                local emsg = errors.format_jcmd_error("Failed", dump_res):gsub("\n", " ")
                table.insert(results.err, save_path .. ": " .. emsg)
              end
              idx = idx + 1
              dump_next()
            end)
          end

          dump_next()
        end

        if #recordings == 1 then
          if always_pick then
            require("nvim-jfr.picker").pick(recordings, {
              title = "Select recording(s) to dump",
              picker = config.picker,
              multi = true,
              preview = false,
              on_confirm = function(selected_recordings)
                local selected = selected_recordings
                if selected_recordings and selected_recordings.rec_num then
                  selected = { selected_recordings }
                end
                if not selected or #selected == 0 then
                  return
                end
                do_dump_many(selected)
              end,
            })
          else
            -- No-args usefulness: when there is only one recording, dump it.
            do_dump_many({ recordings[1] })
          end
          return
        end

        -- Multiple recordings: pick one or more to dump.
        require("nvim-jfr.picker").pick(recordings, {
          title = "Select recording(s) to dump (Enter dumps latest; Tab multi-select)",
          picker = config.picker,
          multi = true,
          preview = false,
          on_confirm = function(selected_recordings)
            local selected = selected_recordings
            if selected_recordings and selected_recordings.rec_num then
              selected = { selected_recordings }
            end
            if not selected or #selected == 0 then
              return
            end
            do_dump_many(selected)
          end,
        })
      end)

    return true
  end

  local function pick_jvm_to_dump()
    local root = project.get_root(0)
    local probe = config.project_jvm_probe or {}
    local jvms = config.project_scoped_jvms and root and jvm_mod.list_for_project(root, {
      probe_system_properties = probe.enabled,
      timeout_ms = probe.timeout_ms,
      max_probes = probe.max_probes,
      time_budget_ms = probe.time_budget_ms,
      stop_after_first_match = probe.stop_after_first_match,
      exclude_raw_patterns = probe.exclude_raw_patterns,
    }) or jvm_mod.list()
    if (#jvms == 0) and config.project_scoped_jvms and root then
      jvms = jvm_mod.list()
    end
    jvms = filter_tooling_jvms(jvms)
    if #jvms == 0 then
      notify_msg(messages.no_jvms())
      return
    end

    require("nvim-jfr.picker").pick(enrich_jvm_items(jvms), {
      title = "Select JVM to dump recording",
      picker = config.picker,
      multi = false,
      preview = false,
      on_confirm = function(selected_jvm)
        local jvm = selected_jvm
        if selected_jvm and selected_jvm[1] then
          jvm = selected_jvm[1]
        end
        if not jvm or not jvm.pid then
          return
        end
        dump_recordings_for_pid(jvm.pid)
      end,
    })
  end

  -- Convenience: if we started a recording in this session, try that JVM first.
  local current_recording = state.get_current_recording()
  if current_recording and current_recording.pid then
    if dump_recordings_for_pid(current_recording.pid, {
      on_no_recordings = function()
        pick_jvm_to_dump()
      end,
    }) then
      return
    end
  end

  -- Otherwise, let user pick a JVM.
  pick_jvm_to_dump()
end

--- Show detected capabilities for a JVM
---
--- Options:
---   --verbose    Include raw VM.version and help JFR.start output
---   --settings=... Check whether a built-in settings value is supported (default/profile)
---
--- Suffix modifiers:
---   :JFRCapabilities!  Same as --verbose
M.capabilities = function(args, cmdopts)
  local jvm_mod = require("nvim-jfr.jvm")
  local config = require("nvim-jfr.config").get()
  local project = require("nvim-jfr.project")
  local caps = require("nvim-jfr.capabilities")
  local cap_ui = require("nvim-jfr.capabilities_ui")
  local messages = require("nvim-jfr.messages")

  local function parse_verbose(a)
    for _, v in ipairs(a or {}) do
      if v == "--verbose" then
        return true
      end
    end
    return false
  end

  local function parse_settings(a)
    local o = M.parse_args(a or {})
    return o.settings
  end

  local root = project.get_root(0)
  local probe = config.project_jvm_probe or {}
  local jvms = config.project_scoped_jvms and root and jvm_mod.list_for_project(root, {
    probe_system_properties = probe.enabled,
    timeout_ms = probe.timeout_ms,
    max_probes = probe.max_probes,
    time_budget_ms = probe.time_budget_ms,
    stop_after_first_match = probe.stop_after_first_match,
    exclude_raw_patterns = probe.exclude_raw_patterns,
  }) or jvm_mod.list()
  if (#jvms == 0) and config.project_scoped_jvms and root then
    jvms = jvm_mod.list()
  end
  jvms = filter_tooling_jvms(jvms)
  if #jvms == 0 then
    notify_msg(messages.no_jvms())
    return
  end

  require("nvim-jfr.picker").pick(enrich_jvm_items(jvms), {
    title = "Select JVM to inspect capabilities",
    picker = config.picker,
    multi = false,
    preview = false,
    on_confirm = function(selected_jvm)
      local jvm = selected_jvm
      if selected_jvm and selected_jvm[1] then
        jvm = selected_jvm[1]
      end
      if not jvm or not jvm.pid then
        return
      end

      local verbose = parse_verbose(args) or (cmdopts and cmdopts.bang == true)
      local settings_override = parse_settings(args)

      caps.detect(jvm.pid, function(cap)
        if not cap or cap.ok == false then
          notify_msg(messages.capabilities_detect_failed(jvm.pid))
          return
        end

        local txt = cap_ui.format(cap, { verbose = verbose, settings_override = settings_override })
        -- For longer content, prefer a scratch buffer (markdown-ish) over
        -- notifications so the user can scroll/search.
        local use_buf = #txt > 900 or txt:find("\n", 1, true) ~= nil
        if use_buf then
          vim.cmd("enew")
          vim.bo[0].buftype = "nofile"
          vim.bo[0].bufhidden = "wipe"
          vim.bo[0].swapfile = false
          vim.bo[0].filetype = "markdown"
          vim.bo[0].modifiable = true
          local lines = vim.split(txt, "\n", { plain = true })
          vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
          vim.bo[0].modifiable = false
          vim.bo[0].readonly = true
          vim.api.nvim_buf_set_name(0, "nvim-jfr-capabilities")
        else
          notify_msg({ text = txt, level = "info" })
        end
      end)
    end,
  })
end

--- List saved .jfr recordings and act on selection.
---
--- Actions:
---  - Enter: open in JMC (when available) or via system opener
---  - :JFRRecordings --delete : delete selected file (with confirmation)
M.recordings = function(args)
  local config = require("nvim-jfr.config").get()
  local rec_mod = require("nvim-jfr.recordings")
  local platform = require("nvim-jfr.platform")
  local messages = require("nvim-jfr.messages")

  local opts = M.parse_args(args or {})
  local do_delete = (opts.delete == "true" or opts.delete == "1")

  local out_dir = rec_mod.get_output_dir(config)
  local ok_dir, err_dir = rec_mod.ensure_output_dir(out_dir)
  if not ok_dir then
    notify_msg(messages.out_dir_prepare_failed(err_dir))
    return
  end

  local files = rec_mod.list_files(out_dir)
  if #files == 0 then
    notify_msg(messages.recordings_none(out_dir))
    return
  end

  require("nvim-jfr.picker").pick(files, {
    title = do_delete and "Select recording(s) to delete" or "Select recording to open",
    on_confirm = function(selected)
      local chosen = selected
      if selected and selected.path then
        chosen = { selected }
      end
      if not chosen or #chosen == 0 then
        return
      end

      if do_delete then
        local ok = vim.fn.confirm(
          string.format("Delete %d recording(s)?", #chosen),
          "&Yes\n&No",
          2
        )
        if ok ~= 1 then
          return
        end

        local errs = {}
        for _, item in ipairs(chosen) do
          local ok_del, err_del = rec_mod.delete_file(item.path)
          if not ok_del then
            table.insert(errs, err_del or ("failed: " .. tostring(item.path)))
          end
        end
        if #errs == 0 then
          notify_msg(messages.recordings_deleted(#chosen))
        else
          notify_msg(messages.recordings_delete_errors(table.concat(errs, "; ")))
        end
        return
      end

      -- open first selected
      local path = chosen[1] and chosen[1].path
      if not path then
        return
      end

      local function open_jfr_file(p)
        if vim.fn.filereadable(p) ~= 1 then
          notify_msg(messages.open_file_not_found(p))
          return
        end

        -- Prefer JMC when configured/available.
        if config.jmc_command and vim.fn.executable(config.jmc_command) == 1 then
          local jmc_cmd = config.jmc_command .. " " .. vim.fn.shellescape(p)
          vim.fn.jobstart(jmc_cmd, {
            detach = true,
            on_exit = function(_, code)
              if code ~= 0 then
                notify_msg(messages.open_jmc_exit(code))
              end
            end,
          })
          notify_msg(messages.opening_jmc(p))
          return
        end

        -- Fallback: open via OS default handler.
        local ok, err = platform.system_open(p)
        if ok then
          notify_msg(messages.opening_default(p))
        else
          notify_msg(messages.open_no_jmc_and_system_open_failed(config.jmc_command, err, p))
        end
      end

      open_jfr_file(path)
    end,
  })
end

return M

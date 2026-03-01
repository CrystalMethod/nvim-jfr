--- Minimal headless checks for nvim-jfr.jvm project-scoped filtering.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.jvm_spec').run())" -c "qa"

local M = {}

local jvm = require("nvim-jfr.jvm")

M.run = function()
  -- system_properties parsing
  local props = jvm._parse_system_properties(table.concat({
    "1234: VM.system_properties",
    "user.dir = /work/myproj",
    "java.runtime.version = 21.0.2+13-LTS",
  }, "\n"))
  assert(props["user.dir"] == "/work/myproj", "expected user.dir parsed")

  -- Ensure list_for_project returns a subset using simple predicate.
  local sample = table.concat({
    "123 /work/myproj/build/classes/java/main com.example.Main",
    "456 /other/elsewhere com.example.Other",
  }, "\n")
  local parsed = jvm.parse_jcmd_output(sample)

  -- Monkeypatch list() just for this spec.
  local old_list = jvm.list
  jvm.list = function()
    return parsed
  end

  local out = jvm.list_for_project("/work/myproj")
  assert(#out == 1 and out[1].pid == 123, "expected only the matching jvm")

  jvm.list = old_list

  -- Fallback probe: when raw matching yields none, system_properties can still match.
  local parsed2 = jvm.parse_jcmd_output(table.concat({
    "111 com.example.Boot",
    "222 com.example.Other",
  }, "\n"))
  local old_list2 = jvm.list
  local old_props = jvm.get_system_properties
  jvm.list = function()
    return parsed2
  end
  jvm.get_system_properties = function(pid)
    if pid == 111 then
      return { ["user.dir"] = "/work/myproj" }
    end
    return { ["user.dir"] = "/tmp" }
  end

  local out2 = jvm.list_for_project("/work/myproj", { max_probes = 2, timeout_ms = 10 })
  assert(#out2 == 1 and out2[1].pid == 111, "expected probe match for pid 111")

  -- Stop early once a match is found (default behavior).
  local n_calls = 0
  jvm.get_system_properties = function(pid)
    n_calls = n_calls + 1
    if pid == 111 then
      return { ["user.dir"] = "/work/myproj" }
    end
    return { ["user.dir"] = "/tmp" }
  end
  local out3 = jvm.list_for_project("/work/myproj", { max_probes = 2, timeout_ms = 10, stop_after_first_match = true })
  assert(#out3 == 1 and out3[1].pid == 111, "expected probe match for pid 111")
  assert(n_calls == 1, "expected early stop after first match")

  -- Exclude patterns prevent tooling JVMs from matching.
  jvm.get_system_properties = function(pid)
    -- Pretend both are in the project dir, but one should be excluded.
    return { ["user.dir"] = "/work/myproj" }
  end
  local out4 = jvm.list_for_project("/work/myproj", {
    max_probes = 2,
    timeout_ms = 10,
    stop_after_first_match = false,
    exclude_raw_patterns = { "equinox" },
  })
  -- parsed2 uses main_class com.example.* (no 'equinox'), so exclude doesn't apply there.
  -- Create a fake list with an equinox raw line.
  local parsed3 = jvm.parse_jcmd_output(table.concat({
    "333 /path/org.eclipse.equinox.launcher_1.0.0.jar",
    "444 com.example.App",
  }, "\n"))
  jvm.list = function()
    return parsed3
  end
  local out5 = jvm.list_for_project("/work/myproj", {
    max_probes = 2,
    timeout_ms = 10,
    stop_after_first_match = false,
    exclude_raw_patterns = { "org%.eclipse%.equinox%.launcher" },
  })
  assert(#out5 == 1 and out5[1].pid == 444, "expected excluded tooling JVM to be filtered")

  -- Exclusions apply to raw-match too (not just probe fallback).
  local parsed4 = jvm.parse_jcmd_output(table.concat({
    "555 /work/myproj org.apache.maven.wrapper.MavenWrapperMain -q",
    "556 /work/myproj com.example.App",
  }, "\n"))
  jvm.list = function()
    return parsed4
  end
  jvm.get_system_properties = old_props
  local out6 = jvm.list_for_project("/work/myproj", {
    probe_system_properties = false,
    exclude_raw_patterns = { "org%.apache%.maven%.wrapper%.MavenWrapperMain" },
  })
  assert(#out6 == 1 and out6[1].pid == 556, "expected Maven wrapper to be excluded from raw matches")

  jvm.list = old_list2
  jvm.get_system_properties = old_props

  -- Best-effort version: should be nil for invalid pid and must not throw.
  local v = jvm.get_java_version("not-a-pid")
  assert(v == nil, "expected nil java version for invalid pid")

  return true
end

return M

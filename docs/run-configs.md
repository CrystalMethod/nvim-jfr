# Named run configurations

`nvim-jfr` can optionally load **project-only** run configurations from:

`<root>/.jfr/run-configs.lua`

Run configs let you name common recording presets (settings, duration, overrides) and select them when starting a recording.

## File format

Create `<root>/.jfr/run-configs.lua`:

```lua
return {
  -- Optional: which config should be treated as the default.
  default = "profile-60s",

  -- Required: map of name -> config.
  configs = {
    ["profile-60s"] = {
      settings = "profile", -- "default" | "profile" | path to .jfc
      duration = "60s",
      start_overrides = {
        maxsize = "250M",
        maxage = "10m",
      },
    },

    ["alloc"] = {
      settings = ".jfr/templates/alloc.jfc",
      duration = "5m",
    },
  },
}
```

## Starting with a run config

Use:

```vim
:JFRStart --run=profile-60s
```

If you don’t pass `--run=...` and the file exists, `:JFRStart` will:

1) prompt for JVM
2) prompt for run config

If the file sets `default = "..."`, that config is presented first in the picker (best-effort) so it behaves like a default choice across picker backends.

## Skipping run config selection

```vim
:JFRStart --run=none
```

This forces “manual mode” (no run config applied).

## What a run config can contain

Each config supports:

- `settings`: `"default" | "profile" | <path-to-.jfc>`
- `duration`: a string like `"60s"`, `"5m"`
- `start_overrides`: a table of extra `JFR.start` options (capability-gated)

Example with overrides:

```lua
return {
  configs = {
    ["profile-capped"] = {
      settings = "profile",
      duration = "60s",
      start_overrides = {
        maxage = "10m",
        maxsize = "250M",
      },
    },
  },
}
```

## Path constraint (required)

When `settings` in a run config is a `.jfc` file, it **must** resolve under:

`<root>/.jfr/templates/`

This keeps run configs portable and project-local.

You can still use any `.jfc` path manually via:

```vim
:JFRStart --settings=/any/path/to/file.jfc
```

## Merge precedence

When a run config is selected:

- CLI args win (e.g. `--duration=...`, `--settings=...`)
- then the run config values
- then your `require("nvim-jfr").setup({ ... })` defaults

If you pass both CLI overrides and run config overrides, they are merged in the same order:

1) `setup().start_overrides`
2) `run-configs.lua` `start_overrides`
3) CLI overrides (`--opt=...` or `--key=value`)

# nvim-jfr

Control Java Flight Recorder (JFR) from Neovim.

- Start / stop / dump recordings via `jcmd`
- Monitor active recordings in-editor
- Save recordings under your project (`<root>/.jfr/recordings`)
- Open `.jfr` in JDK Mission Control (JMC)

## What is nvim-jfr?

**nvim-jfr** brings the common “profile a JVM” loop into your editor:

1. Start a recording
2. Monitor while it runs
3. Stop (or dump) to a `.jfr` file
4. Open the result in JMC
5. Browse/manage recordings

It is designed around a project-local layout:

- Recordings: `<root>/.jfr/recordings/`
- Templates: `<root>/.jfr/templates/`

For the shortest guide, see: **[docs/recording-workflow.md](docs/recording-workflow.md)**

## Installation

### Prerequisites

- Neovim **0.8.0+**
- JDK **8+** with `jcmd` available on `PATH`

Optional:

- `jmc` (or a configured `jmc_command`) to open recordings in Mission Control
- `jfr` to enable `:JFRRecordings` preview (`jfr summary`) when enabled

### Setup with your plugin manager

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "CrystalMethod/nvim-jfr",
   cmd = { "JFRStart", "JFRStatus", "JFRStop", "JFRDump", "JFRRecordings" },
   opts = {},
 }
```

If you want *all* commands available for lazy-loading:

```lua
{
  "CrystalMethod/nvim-jfr",
  cmd = {
    "JFRStart",
    "JFRStop",
    "JFRDump",
    "JFRStatus",
    "JFRRecordings",
    "JFRCapabilities",
    "JFCNew",
  },
  opts = {},
}
```

## Quick Start

```vim
" 1) Start a recording
:JFRStart --settings=profile --duration=60s

" Skip named run configuration selection (if you use run configs)
:JFRStart --run=none

" 2) Monitor while it runs
:JFRStatus

" 3) Stop + save (or dump without stopping)
:JFRStop
" or:
:JFRDump

" 4) Browse/manage saved recordings
:JFRRecordings
```

## Commands

### Recommended (core workflow)

| Command | Purpose | Typical usage |
|---------|---------|---------------|
| `:JFRStart` | Start a recording | `:JFRStart --settings=profile --duration=60s` |
| `:JFRStatus` | Monitor active recordings | `:JFRStatus` |
| `:JFRStop` | Stop + save recording(s) | `:JFRStop` |
| `:JFRDump` | Dump without stopping | `:JFRDump` |
| `:JFRRecordings` | Browse/manage saved `.jfr` files | `:JFRRecordings` |

### Advanced / optional

| Command | When to use |
|---------|-------------|
| `:JFRCapabilities` | Inspect what the target JVM supports (option gating, `JFR.start` help, etc.) |
| `:JFCNew` | Copy a `.jfc` template into `<root>/.jfr/templates/` |

### Command behavior notes

Stop all recordings for a JVM:

```vim
:JFRStop --all=true   " confirm
:JFRStop!             " no confirmation
```

Dump selection behavior:

```vim
:JFRDump              " dumps the latest/only recording (no-args is useful)
:JFRDump!             " always pick recording(s)
:JFRDump --pick=true  " always pick recording(s)
```

## Core features

### Project-scoped output

When `output_dir = "project"` (default), recordings are saved under:

`<root>/.jfr/recordings/`

### Project-local JFC templates

Create a project-local `.jfc` from a template:

```vim
:JFCNew
```

Then start a recording using it:

```vim
:JFRStart --settings=<root>/.jfr/templates/your.jfc --duration=60s
```

For editing `.jfc` (XML), use an XML LSP (e.g. LemMinX) for validation/formatting.

See also: **[docs/jfc-authoring.md](docs/jfc-authoring.md)**.

## Configuration

For the complete configuration reference, see **[CONFIG.md](CONFIG.md)**.

Optional: named run configurations: **[docs/run-configs.md](docs/run-configs.md)**.

Note: if you have many JVMs running, keep pickers snappy by leaving
`show_java_version_in_picker = false` (default) and by excluding tooling JVMs
(jdtls, mvnw, etc.) via `project_jvm_probe.exclude_raw_patterns` (see CONFIG).

```lua
require("nvim-jfr").setup({
  -- Output directory for recordings
  -- "project" = <project-root>/.jfr/recordings when a project root is detected
  -- nil = platform default (~/jfr-recordings on Unix, %USERPROFILE%\jfr-recordings on Windows)
  output_dir = "project",

  -- Default `settings=` value passed to `jcmd <pid> JFR.start`.
  -- Supported values:
  --  - "default" | "profile" (built-in templates)
  --  - "/path/to/custom.jfc" (custom settings file)
  settings = "profile",

  -- Picker: "snacks", "telescope", "fzf", "vim", "auto"
  picker = "auto",

  -- Command to open JFR files (JDK Mission Control)
  jmc_command = "jmc",

})
```

## Workflow examples

### Quick profiling loop

```vim
:JFRStart --settings=profile --duration=60s
:JFRStatus
:JFRStop
:JFRRecordings
```

### Dump without stopping (e.g. take snapshots)

```vim
:JFRDump
```

### Save all outputs under the project

Set `output_dir = "project"` (this is the default).

## Healthcheck

Run:

```vim
:checkhealth nvim-jfr
```

This checks:

- Neovim version and required APIs (`vim.fs.find`, `vim.uv`/`vim.loop`)
- Your `nvim-jfr` configuration (common type/value mistakes)
- Picker backend availability (Snacks/Telescope/fzf-lua/vim.ui.select)
- Output directory resolution + basic writability checks
- External tools on `PATH` (or via config): `jcmd`/`java` (required), `jfr`/`jmc` (optional)

## Troubleshooting

### “No running JVM processes found”

- Ensure your Java application is running
- Verify `jcmd -l` works from a terminal

### “JFR is not enabled/available for this JVM”

- For JDK 8, start the JVM with: `-XX:+UnlockCommercialFeatures -XX:+FlightRecorder` (or vendor equivalent)
- Check: `jcmd <pid> help JFR.start`

### Permission / attach failures

- Run Neovim as the same OS user that owns the JVM process
- On Linux, check ptrace restrictions (e.g. `/proc/sys/kernel/yama/ptrace_scope`)

## Getting help

- `:checkhealth nvim-jfr`
- Open an issue with:
  - your OS + Neovim version
  - your JDK version
  - the output of `:checkhealth nvim-jfr`

---

# For developers

## Project structure

```
nvim-jfr/
├── plugin/
│   └── nvim-jfr.lua          # User command registration
├── lua/nvim-jfr/
│   ├── commands.lua          # :JFR* command implementations
│   ├── jfr.lua               # jcmd wrapper + JFR.* operations
│   ├── jvm.lua               # JVM discovery (jcmd -l)
│   ├── status.lua            # Status UI
│   ├── recordings.lua        # Output dir + file helpers
│   ├── picker.lua            # Picker abstraction
│   └── ...
└── docs/                           # Additional markdown docs
    └── recording-workflow.md
```

## Testing (headless)

This repo uses small headless specs that can be executed with Neovim:

```bash
nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.commands_spec').run())" -c "qa"
```

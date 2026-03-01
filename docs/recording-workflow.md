# Recording workflow (nvim-jfr)

This is the shortest “happy path” for profiling a JVM with Java Flight Recorder from inside Neovim.

## Project layout

When nvim-jfr detects a project root, it uses these project-local paths:

- Recordings: `<root>/.jfr/recordings/` (`*.jfr`)
- Templates: `<root>/.jfr/templates/` (`*.jfc`)

## Core commands (minimal)

1) **Start a recording**

```vim
:JFRStart --settings=profile --duration=60s
```

2) **Monitor while it runs**

```vim
:JFRStatus
```

3) **Stop and save** (or dump without stopping)

```vim
:JFRStop
" or:
:JFRDump
```

4) **Browse/manage saved recordings**

```vim
:JFRRecordings
" delete from the picker:
:JFRRecordings --delete=true
```

### Notes (beyond the happy path)

#### Opening recordings

`:JFRRecordings` is also how you **open** recordings:

- Select a `.jfr` to open it.
- If `jmc_command` is available, nvim-jfr will open the file in **JDK Mission Control**.
- Otherwise it falls back to your OS “open” handler (e.g. `open`/`xdg-open`).

#### Sidecar metadata (`*.jfr.json`)

When you save a recording via `:JFRStop` or `:JFRDump`, nvim-jfr writes a sidecar JSON file next to it:

- `foo.jfr` → `foo.jfr.json`

This captures *how the recording was produced* (selected run config name, effective settings, overrides, JVM info), using **relative paths** when possible.

If you delete a recording via `:JFRRecordings --delete=true`, the sidecar is deleted too.

#### Stopping multiple recordings

Stop all recordings for the selected JVM:

```vim
:JFRStop --all=true   " confirm
:JFRStop!             " no confirmation
```

#### Dump selection behavior

```vim
:JFRDump              " dumps the latest/only recording (useful with no args)
:JFRDump!             " always pick recording(s)
:JFRDump --pick=true  " always pick recording(s)
```

#### Named run configurations (optional)

If `<root>/.jfr/run-configs.lua` exists, `:JFRStart` will prompt for a run config after JVM selection.

```vim
:JFRStart --run=profile-60s
:JFRStart --run=none  " skip run config selection/application
```

See: **[docs/run-configs.md](run-configs.md)**

#### Per-recording start overrides

You can pass additional `JFR.start` options as overrides:

```vim
:JFRStart --opt=maxage=10m --opt=maxsize=250M
" or:
:JFRStart --maxage=10m --maxsize=250M
```

Unsupported overrides are ignored (capability-gated) and reported.

## Optional: create project-local settings (`.jfc`)

Use `:JFCNew` to copy a template into `<root>/.jfr/templates/` and edit it.

Then start a recording with that settings file:

```vim
:JFRStart --settings=<root>/.jfr/templates/your.jfc --duration=60s
```

Tip: for authoring `.jfc` (XML), use an XML LSP (e.g. LemMinX) for validation/formatting.

See: **[docs/jfc-authoring.md](jfc-authoring.md)**

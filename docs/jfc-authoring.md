# Authoring JFR settings (.jfc)

`.jfc` files are **XML** (JFR configuration). `nvim-jfr` intentionally does not ship `:JFCFormat` / `:JFCValidate` commands; instead, use standard Neovim XML tooling.

## 1) Ensure `.jfc` is detected as XML

Neovim often detects `.jfc` as `xml` automatically. If it does not, add:

```lua
vim.filetype.add({
  extension = {
    jfc = "xml",
  },
})
```

## 2) XML LSP (recommended): LemMinX

LemMinX provides diagnostics and formatting.

### Option A: mason.nvim + nvim-lspconfig (lazy.nvim)

```lua
{
  "williamboman/mason.nvim",
  config = true,
},
{
  "williamboman/mason-lspconfig.nvim",
  opts = {
    ensure_installed = { "lemminx" },
  },
},
{
  "neovim/nvim-lspconfig",
  config = function()
    require("lspconfig").lemminx.setup({})
  end,
},
```

### Option B: nvim-lspconfig only

If you manage servers yourself, you can still configure LemMinX via lspconfig:

```lua
require("lspconfig").lemminx.setup({})
```

## 3) Treesitter highlighting (optional)

```lua
{
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  opts = {
    ensure_installed = { "xml" },
  },
}
```

## 4) Formatting

Preferred: use LSP formatting when LemMinX is attached:

```vim
:lua vim.lsp.buf.format({ async = true })
```

Alternative: use an external formatter (e.g. `xmllint`) with your formatting plugin of choice.

## How nvim-jfr uses `.jfc`

`nvim-jfr` passes your selected settings to `jcmd <pid> JFR.start settings=...`.

- Built-ins: `--settings=default` or `--settings=profile`
- Custom file: `--settings=/path/to/file.jfc`

If you use **named run configs** (`<root>/.jfr/run-configs.lua`), any `.jfc` referenced there must live under:

`<root>/.jfr/templates/`

This keeps run configs portable and avoids leaking machine-specific paths.

## Troubleshooting

- **No diagnostics / no formatting**: check `:LspInfo` in a `.jfc` buffer and confirm `lemminx` is attached.
- **LemMinX fails to start**: ensure a Java runtime is available (Mason-managed LemMinX still needs `java` on `PATH`).
- **External formatting with `xmllint`**: install libxml2 (macOS: `brew install libxml2`) and ensure `xmllint` is on `PATH`.

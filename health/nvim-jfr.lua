--- Runtime healthcheck entry for :checkhealth nvim-jfr.
---
--- Neovim discovers healthchecks under runtimepath: health/{name}.lua
--- Delegate to lua module for testability.

require("nvim-jfr.health").check()

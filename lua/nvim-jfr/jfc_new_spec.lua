--- Headless checks for creating a new .jfc from a template.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+.=" -c "lua assert(require('nvim-jfr.jfc_new_spec').run())" -c "qa"

local M = {}

M.run = function()
  local jfc = require("nvim-jfr.jfc")
  local platform = require("nvim-jfr.platform")

  local tmp = vim.fn.tempname() .. "_jfc_new"
  vim.fn.mkdir(tmp, "p")

  local src = platform.join_path(tmp, "template.jfc")
  local dest = platform.join_path(tmp, "out", "new.jfc")
  local f = assert(io.open(src, "w"))
  f:write("<?xml version='1.0' encoding='UTF-8'?>\n")
  f:write("<configuration>\n")
  f:write("</configuration>\n")
  f:close()

  local ok, err = jfc.copy_template(src, dest, { overwrite = false })
  assert(ok == true, err)
  assert(vim.fn.filereadable(dest) == 1)

  -- should fail without overwrite
  local ok2 = jfc.copy_template(src, dest, { overwrite = false })
  assert(ok2 == false)

  -- should succeed with overwrite
  local ok3, err3 = jfc.copy_template(src, dest, { overwrite = true })
  assert(ok3 == true, err3)

  vim.fn.delete(tmp, "rf")
  return true
end

return M

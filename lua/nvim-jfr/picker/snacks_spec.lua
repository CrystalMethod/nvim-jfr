--- Minimal unit-style spec for snacks picker selection plumbing
--
-- This can be run headless and does not require snacks.nvim.
-- It verifies that `_extract_originals` correctly returns the original
-- objects associated with selected picker items.

local M = {}

M.run = function()
  local snacks_picker = require("nvim-jfr.picker.snacks")

  local orig1 = { rec_num = 1, filename = "a.jfr" }
  local orig2 = { rec_num = 2, filename = "b.jfr" }
  local it1 = { _orig = orig1 }
  local it2 = { _orig = orig2 }

  -- Multi-select path using official picker:selected API
  local fake_picker_selected = {
    selected = function(_, _opts)
      return { it1, it2 }
    end,
  }
  local out = snacks_picker._extract_originals(fake_picker_selected)
  assert(#out == 2, "expected 2 selected originals")
  assert(out[1] == orig1 and out[2] == orig2, "expected originals to match")

  -- Fallback path using picker.selection field
  local fake_picker_selection = { selection = { it2 } }
  local out2 = snacks_picker._extract_originals(fake_picker_selection)
  assert(#out2 == 1 and out2[1] == orig2, "expected fallback originals")

  return true
end

return M

--- Snacks picker implementation
--- @module nvim-jfr.picker.snacks

local M = {}

local function set_preview_text(ctx, text)
    if not ctx or not ctx.buf then
        return
    end
    local lines = vim.split(text or "", "\n", { plain = true })
    vim.bo[ctx.buf].modifiable = true
    vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, lines)
    vim.bo[ctx.buf].modifiable = false
    vim.bo[ctx.buf].filetype = "markdown"
end

-- Optional: allow caller to fully disable preview for non-file pickers.
-- Default: preview on (for recordings) if config enables it.
local function preview_allowed(opts)
    if not opts then
        return true
    end
    if opts.preview == false then
        return false
    end
    return true
end

-- Extract original items from a snacks picker.
-- Prefer the official `picker:selected({ fallback = true })` API so that
-- multi-select and single-select both work reliably.
---@param picker table Snacks picker instance
---@return table originals
M._extract_originals = function(picker)
    local selected = {}

    if picker and type(picker.selected) == "function" then
        selected = picker:selected({ fallback = true })
    elseif picker and type(picker.selection) == "table" then
        -- Older/internal field fallback.
        selected = picker.selection
    end

    local originals = {}
    for _, it in ipairs(selected or {}) do
        if type(it) == "table" and it._orig ~= nil then
            table.insert(originals, it._orig)
        end
    end
    return originals
end

--- Pick using snacks.picker
---@param items table List of items
---@param opts table Options: {title, format, on_confirm}
M.pick = function(items, opts)
    local snacks = require("snacks.picker")

    -- Build items with proper display
    local display_items = {}
    for _, item in ipairs(items) do
        local display
        -- Detect item type by available fields
        if item.pid and item.main_class then
            -- JVM item
            if item.java_version and tostring(item.java_version) ~= "" then
                display = string.format("%d - %s (Java %s)", item.pid, item.main_class, tostring(item.java_version))
            else
                display = string.format("%d - %s", item.pid, item.main_class)
            end
        elseif item.display then
            -- Has display field
            display = item.display
        else
            -- Generic fallback
            display = tostring(item)
        end

        -- Create the picker item - ensure it's a proper string for matching
        local picker_item = {
            text = display, -- Primary text for matching
            file = display, -- For display
            _orig = item, -- Store original for callback
        }
        table.insert(display_items, picker_item)
    end

    local config = require("nvim-jfr.config").get()
    local preview_cfg = config.recordings_preview or {}

    -- Base picker options
    local picker_opts = {
        title = opts.title or "Select",
        items = display_items,
        format = function(item, _p)
            return { { item.file, "SnacksPickerTitle" } }
        end,
        layout = {
            -- Snacks has built-in layout presets (default shows preview on the right).
            preset = preview_cfg.layout_preset or "default",
            preview = preview_allowed(opts) and (preview_cfg.enabled ~= false),
        },
        preview = function(ctx)
            if not preview_allowed(opts) or preview_cfg.enabled == false then
                return false
            end

            local orig = ctx and ctx.item and ctx.item._orig
            local path = orig and orig.path
            if not path then
                return false
            end

            local preview = require("nvim-jfr.preview.recording")
            preview.render_async(path, preview_cfg, function(text)
                -- Ensure we only update the current preview buffer.
                if not ctx or not vim.api.nvim_buf_is_valid(ctx.buf) then
                    return
                end
                set_preview_text(ctx, text)
            end)
            return true
        end,
        confirm = function(picker, item)
            picker:close()
            if not opts.on_confirm then
                return
            end

            -- Always derive selections from picker state.
            -- Do not rely on the `item` parameter: it may not reflect multi-select.
            local originals = M._extract_originals(picker)
            if #originals > 0 then
                opts.on_confirm(originals)
            end
        end,
    }

    -- Note: Tab multi-select is always enabled in snacks

    snacks.pick(picker_opts)
end

return M

--- nvim-jfr plugin entry point
--- This file is loaded automatically by Neovim

-- Version check
if vim.fn.has("nvim-0.8.0") ~= 1 then
    vim.api.nvim_err_writeln("nvim-jfr requires Neovim 0.8.0 or later")
    return
end

-- Load the main module
local nvim_jfr = require("nvim-jfr")

-- Refresh project context on directory/buffer switches (if enabled)
pcall(function()
    require("nvim-jfr.context").setup()
end)

-- Create user commands
vim.api.nvim_create_user_command("JFRStart", function(opts)
    require("nvim-jfr.commands").start(opts.fargs)
end, {
    nargs = "*",
    desc = "Start a JFR recording",
    complete = function()
        return {
            "--duration=60s",
            "--name=recording",
            "--filename=recording.jfr",
            "--settings=profile",
            "--settings=default",
            "--settings=/path/to/settings.jfc",
            "--run=my-config",
            "--run=none",
            "--opt=maxage=10m",
            "--opt=maxsize=250M",
        }
    end,
})

vim.api.nvim_create_user_command("JFRStop", function(opts)
    require("nvim-jfr.commands").stop(opts.fargs, { bang = opts.bang })
end, {
    nargs = "*",
    bang = true,
    desc = "Stop a JFR recording",
    complete = function()
        return { "--filename=recording.jfr", "--all=true" }
    end,
})

vim.api.nvim_create_user_command("JFRDump", function(opts)
    require("nvim-jfr.commands").dump(opts.fargs, { bang = opts.bang })
end, {
    nargs = "*",
    bang = true,
    desc = "Dump a JFR recording",
    complete = function()
        return { "--filename=dump.jfr", "--pick=true" }
    end,
})

vim.api.nvim_create_user_command("JFRStatus", function()
    require("nvim-jfr.commands").status()
end, {
    nargs = 0,
    desc = "Show active recordings in a status window",
})

vim.api.nvim_create_user_command("JFRRecordings", function(opts)
    require("nvim-jfr.commands").recordings(opts.fargs)
end, {
    nargs = "*",
    desc = "List saved .jfr recordings (open or delete)",
    complete = function()
        return { "--delete=true" }
    end,
})

vim.api.nvim_create_user_command("JFRCapabilities", function(opts)
    require("nvim-jfr.commands").capabilities(opts.fargs, { bang = opts.bang })
end, {
    nargs = "*",
    bang = true,
    desc = "Show detected JFR/JDK capabilities for a JVM",
    complete = function()
        return { "--verbose", "--settings=profile", "--settings=default" }
    end,
})

vim.api.nvim_create_user_command("JFCNew", function()
    require("nvim-jfr.commands").jfc_new_from_template()
end, {
    nargs = 0,
    desc = "Create a new project-local .jfc from a template",
})

return nvim_jfr

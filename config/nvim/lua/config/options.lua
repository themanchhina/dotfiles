-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Load compatibility shims for Neovim 0.12+, Treesitter, and Mason
require("config.compat")

vim.opt.scrolloff = 16

-- Universal clipboard provider using OSC 52 & system pasteboard
-- Bridges directly to WezTerm, Herdr, and remote SSH sessions
-- Bypasses macOS launchd/Mach bootstrap namespace failures with pbcopy
local clip_cache = { ["+"] = {}, ["*"] = {} }
local osc52 = require("vim.ui.clipboard.osc52")

local function copy_with_osc52(reg)
  local osc52_copy = osc52.copy(reg)
  local clip_id = reg == "+" and "c" or "p"
  return function(lines, regtype)
    clip_cache[reg] = { lines = lines, regtype = regtype or "l" }

    -- 1. Built-in Neovim OSC 52 handler (via nvim_ui_send)
    pcall(osc52_copy, lines)

    -- 2. Direct OSC 52 sequence to stdout to ensure reception across nested PTYs
    local text = table.concat(lines, "\n")
    local encoded = vim.base64.encode(text)
    local seq = string.format("\027]52;%s;%s\027\\", clip_id, encoded)
    pcall(function()
      io.stdout:write(seq)
      io.stdout:flush()
    end)

    -- 3. System pbcopy fallback if running in a session where pbcopy works
    pcall(function()
      vim.fn.system({ "pbcopy" }, text)
    end)
  end
end

local function paste_clipboard(reg)
  return function()
    local ok, out = pcall(vim.fn.systemlist, { "pbpaste" })
    if ok and vim.v.shell_error == 0 and type(out) == "table" and #out > 0 then
      return { out, "l" }
    end
    if clip_cache[reg] and clip_cache[reg].lines and #clip_cache[reg].lines > 0 then
      return { clip_cache[reg].lines, clip_cache[reg].regtype or "l" }
    end
    return { {}, "v" }
  end
end

vim.g.clipboard = {
  name = "OSC 52 / System",
  copy = {
    ["+"] = copy_with_osc52("+"),
    ["*"] = copy_with_osc52("*"),
  },
  paste = {
    ["+"] = paste_clipboard("+"),
    ["*"] = paste_clipboard("*"),
  },
}
vim.opt.clipboard = "unnamedplus"

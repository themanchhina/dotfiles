-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.opt.scrolloff = 16

-- Universal clipboard provider using OSC 52 & system pasteboard
-- Bridges directly to WezTerm, Herdr, and remote SSH sessions
-- Bypasses macOS launchd/Mach bootstrap namespace failures with pbcopy
local clip_cache = { ["+"] = {}, ["*"] = {} }
local osc52 = require("vim.ui.clipboard.osc52")

-- Per-OS: this tree is synced to Linux remotes, which have no pbcopy/pbpaste.
local function first_executable(candidates)
  for _, cmd in ipairs(candidates) do
    if vim.fn.executable(cmd[1]) == 1 then return cmd end
  end
end
local copy_cmd = first_executable({ { "pbcopy" }, { "wl-copy" }, { "xclip", "-selection", "clipboard" }, { "xsel", "-bi" } })
local paste_cmd = first_executable({ { "pbpaste" }, { "wl-paste" }, { "xclip", "-selection", "clipboard", "-o" }, { "xsel", "-b" } })

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

    -- 3. System pasteboard fallback if running in a session where it works
    if copy_cmd then
      pcall(function()
        vim.fn.system(copy_cmd, text)
      end)
    end
  end
end

local function paste_clipboard(reg)
  return function()
    -- Not systemlist: the trailing newline is the only linewise/charwise signal.
    if paste_cmd then
      local ok, out = pcall(vim.fn.system, paste_cmd)
      if ok and vim.v.shell_error == 0 and type(out) == "string" and out ~= "" then
        local regtype = out:sub(-1) == "\n" and "l" or "v"
        return { vim.split((out:gsub("\n$", "")), "\n"), regtype }
      end
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

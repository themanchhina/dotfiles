vim.opt.scrolloff = 16

-- OSC 52 reaches the Mac through SSH/Herdr; cache yanks when system paste is unavailable.
local clip_cache = { ["+"] = {}, ["*"] = {} }
local osc52 = require("vim.ui.clipboard.osc52")

local function first_executable(candidates)
  for _, cmd in ipairs(candidates) do
    if vim.fn.executable(cmd[1]) == 1 then return cmd end
  end
end
local copy_cmd = first_executable({ { "pbcopy" }, { "wl-copy" }, { "xclip", "-selection", "clipboard" }, { "xsel", "-bi" } })
-- wl-paste needs -n: it appends a newline otherwise, which reads back as linewise.
local paste_cmd = first_executable({ { "pbpaste" }, { "wl-paste", "-n" }, { "xclip", "-selection", "clipboard", "-o" }, { "xsel", "-b" } })

local function copy_with_osc52(reg)
  local osc52_copy = osc52.copy(reg)
  return function(lines, regtype)
    clip_cache[reg] = { lines = lines, regtype = regtype or "l" }

    pcall(osc52_copy, lines)

    -- Do not append a newline: linewise already carries a final empty element.
    if copy_cmd then
      local text = table.concat(lines, "\n")
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
      if ok and vim.v.shell_error == 0 and type(out) == "string" then
        -- A charwise yank ending at end-of-line writes the same bytes as linewise,
        -- so trust the cached regtype when the text still matches.
        local cached = clip_cache[reg]
        if cached and cached.lines and table.concat(cached.lines, "\n") == out then
          return { cached.lines, cached.regtype }
        end
        local regtype = out:sub(-1) == "\n" and "l" or "v"
        return { out == "" and {} or vim.split((out:gsub("\n$", "")), "\n"), regtype }
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

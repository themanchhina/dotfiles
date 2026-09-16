local root = vim.env.TEST_ROOT or vim.fn.getcwd()
local failures = 0
local function check(value, message)
  if not value then
    failures = failures + 1
    vim.api.nvim_err_writeln(message)
  end
end

-- Use private fake commands so this test never reads or writes the real clipboard.
local bin = vim.fn.tempname()
vim.fn.mkdir(bin, "p")
vim.fn.writefile({ "#!/bin/sh", "printf '%s' \"$TEST_CLIPBOARD\"" }, bin .. "/pbpaste")
vim.fn.writefile({ "#!/bin/sh", "/bin/cat >/dev/null" }, bin .. "/pbcopy")
vim.fn.system({ "chmod", "+x", bin .. "/pbpaste", bin .. "/pbcopy" })
vim.env.PATH = bin
local osc52_copies, stdout_writes = 0, 0
package.loaded["vim.ui.clipboard.osc52"] = {
  copy = function()
    return function() osc52_copies = osc52_copies + 1 end
  end,
}
io.stdout = { write = function() stdout_writes = stdout_writes + 1 end, flush = function() end }
dofile(root .. "/config/nvim/lua/config/options.lua")

local copy = vim.g.clipboard.copy["+"]
local paste = vim.g.clipboard.paste["+"]
copy({ "old" }, "V")
check(osc52_copies == 1 and stdout_writes == 0, "copy must use one native OSC 52 emission")
vim.env.TEST_CLIPBOARD = ""
local empty = paste()
check(#empty[1] == 0 and empty[2] == "v", "successful empty clipboard reused stale cache")

for _, sample in ipairs({
  { { "character" }, "v", "character" },
  { { "line", "" }, "V", "line\n" },
  { { "block", "text" }, "\0225", "block\ntext" },
}) do
  copy(sample[1], sample[2])
  vim.env.TEST_CLIPBOARD = sample[3]
  local got = paste()
  check(vim.deep_equal(got, { sample[1], sample[2] }), "cached clipboard type was not preserved: " .. sample[2])
end

vim.fn.delete(bin, "rf")
if failures > 0 then vim.cmd("cquit 1") end

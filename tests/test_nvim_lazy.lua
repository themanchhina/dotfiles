local root = vim.env.TEST_ROOT or vim.fn.getcwd()
local original_stat, original_system, original_exit = vim.uv.fs_stat, vim.fn.system, os.exit

vim.uv.fs_stat = function() return nil end
vim.fn.system({ "false" })
vim.fn.system = function()
  return "clone failed"
end
vim.fn.getchar = function() error("headless startup prompted for input") end
os.exit = function(code) error("exit:" .. code) end

local ok, err = pcall(dofile, root .. "/config/nvim/lua/config/lazy.lua")
vim.uv.fs_stat, vim.fn.system, os.exit = original_stat, original_system, original_exit
assert(not ok and tostring(err):find("exit:1", 1, true), tostring(err))

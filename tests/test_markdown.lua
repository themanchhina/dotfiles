-- Run with: nvim -u NONE -i NONE --headless -l tests/test_markdown.lua
local directory = vim.fn.tempname()
local original_has, original_expand, original_notify = vim.fn.has, vim.fn.expand, vim.notify
vim.fn.has = function(feature) return feature == "mac" and 0 or original_has(feature) end
vim.fn.expand = function(path) return path == "~/.cache/dotfiles" and directory or original_expand(path) end
vim.notify = function() end
local plugin = dofile("config/nvim/lua/plugins/markdown-preview.lua")[1]
plugin.init()
assert(vim.g.mkdp_port == "8765" and vim.g.mkdp_open_to_the_world == 0)
vim.fn[vim.g.mkdp_browserfunc]("http://127.0.0.1:8765/page/42")
assert(vim.fn.readfile(directory .. "/markdown-preview.url")[1] == "http://127.0.0.1:8765/page/42")
vim.fn[vim.g.mkdp_browserfunc]("http://127.0.0.1:8765/page/43")
assert(#vim.fn.readfile(directory .. "/markdown-preview.url") == 2, "second preview must reach the tailing browser bridge")
vim.fn.delete(directory, "rf")
vim.fn.has, vim.fn.expand, vim.notify = original_has, original_expand, original_notify
print("Markdown browser handoff passed")

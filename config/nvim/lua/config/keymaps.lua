-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("x", "p", "P", { desc = "Paste without replacing register" })
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Enter Normal Mode" })
vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Scroll Down and Center" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Scroll Up and Center" })

-- Unified split shortcuts matching Herdr's mental model (v for vertical, - for horizontal)
-- Window navigation inside Neovim uses <C-h/j/k/l>
-- Multiplexer navigation across Herdr panes uses <C-A-h/j/k/l> (Ctrl+Alt+hjkl)
vim.keymap.set("n", "<leader>v", "<C-w>v", { desc = "Split Window Right (Vertical)" })
vim.keymap.set("n", "<leader>-", "<C-w>s", { desc = "Split Window Below (Horizontal)" })
vim.keymap.set("n", "<leader>wx", "<C-w>c", { desc = "Close Current Window" })

-- Auto-copy mouse selection on release (matches Herdr's copy-on-select mental model)
-- Automatically copies visual selection to system clipboard upon mouse release
vim.keymap.set("v", "<LeftRelease>", [["+y<LeftRelease>]], { desc = "Auto-copy mouse selection to clipboard" })


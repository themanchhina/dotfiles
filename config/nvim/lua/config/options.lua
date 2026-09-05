-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.opt.scrolloff = 16

-- Neovim 0.12+ quantified captures compatibility shim for treesitter query directives
if vim.treesitter then
  local orig_get_range = vim.treesitter.get_range
  if orig_get_range then
    vim.treesitter.get_range = function(node, source, metadata)
      if type(node) == "table" and node[1] and type(node.range) ~= "function" then
        node = node[1]
      end
      return orig_get_range(node, source, metadata)
    end
  end

  local orig_get_node_text = vim.treesitter.get_node_text
  if orig_get_node_text then
    vim.treesitter.get_node_text = function(node, source, opts)
      if type(node) == "table" and node[1] and type(node.range) ~= "function" then
        node = node[1]
      end
      return orig_get_node_text(node, source, opts)
    end
  end
end

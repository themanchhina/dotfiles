-- config/nvim/lua/config/compat.lua
-- Compatibility shims and runtime patches for Neovim 0.12+, Treesitter, and Mason.

local M = {}

-- 1. Neovim 0.12+ quantified captures compatibility shim for treesitter query directives & predicates.
-- In Neovim 0.12, quantified captures match tables of TSNodes (e.g. { TSNode, ... } or empty {}).
-- Legacy or external query directives/predicates pass these tables (or nil) to get_node_text / get_range,
-- which expect a single TSNode with a :range() method. Calling :range() on nil or {} crashes decoration
-- providers (e.g. conceal_line) and dumps a stack trace on startup.
if vim.treesitter then
  local function unwrap_ts_node(node)
    if not node then
      return nil
    end
    local ok, has_range = pcall(function()
      return type(node.range) == "function"
    end)
    if ok and has_range then
      return node
    end
    if type(node) == "table" then
      for _, item in ipairs(node) do
        local unwrapped = unwrap_ts_node(item)
        if unwrapped then
          return unwrapped
        end
      end
    end
    return nil
  end

  local orig_get_range = vim.treesitter.get_range
  if orig_get_range then
    vim.treesitter.get_range = function(node, source, metadata)
      local n = unwrap_ts_node(node)
      if not n then
        return { 0, 0, 0, 0, 0, 0 }
      end
      local ok, res = pcall(orig_get_range, n, source, metadata)
      if ok and res then
        return res
      end
      return { 0, 0, 0, 0, 0, 0 }
    end
  end

  local orig_get_node_text = vim.treesitter.get_node_text
  if orig_get_node_text then
    vim.treesitter.get_node_text = function(node, source, opts)
      local n = unwrap_ts_node(node)
      if not n then
        return ""
      end
      local ok, res = pcall(orig_get_node_text, n, source, opts)
      if ok and res then
        return res
      end
      return ""
    end
  end

  local orig_is_in_node_range = vim.treesitter.is_in_node_range
  if orig_is_in_node_range then
    vim.treesitter.is_in_node_range = function(node, line, col)
      local n = unwrap_ts_node(node)
      if not n then
        return false
      end
      local ok, res = pcall(orig_is_in_node_range, n, line, col)
      return ok and res or false
    end
  end

  local orig_node_contains = vim.treesitter.node_contains
  if orig_node_contains then
    vim.treesitter.node_contains = function(node, range)
      local n = unwrap_ts_node(node)
      if not n then
        return false
      end
      local ok, res = pcall(orig_node_contains, n, range)
      return ok and res or false
    end
  end

  local orig_get_node_range = vim.treesitter.get_node_range
  if orig_get_node_range then
    vim.treesitter.get_node_range = function(node_or_range)
      local n = unwrap_ts_node(node_or_range)
      if not n then
        if type(node_or_range) == "table" and #node_or_range >= 4 then
          local ok, r1, r2, r3, r4 = pcall(orig_get_node_range, node_or_range)
          if ok and r1 ~= nil then
            return r1, r2, r3, r4
          end
        end
        return 0, 0, 0, 0
      end
      local ok, r1, r2, r3, r4 = pcall(orig_get_node_range, n)
      if ok and r1 ~= nil then
        return r1, r2, r3, r4
      end
      return 0, 0, 0, 0
    end
  end
end

-- 2. Clean up stale master-branch leftover files from nvim-treesitter if present.
-- When nvim-treesitter transitions from master to main, the legacy lua/nvim-treesitter.lua file
-- (which requires nvim-treesitter.configs and query_predicates) can linger on disk as an untracked file,
-- shadowing the new lua/nvim-treesitter/init.lua directory module.
local data_dir = vim.fn.stdpath("data")
local stale_ts_entry = vim.fs.joinpath(data_dir, "lazy", "nvim-treesitter", "lua", "nvim-treesitter.lua")
if vim.uv.fs_stat(stale_ts_entry) then
  pcall(vim.uv.fs_unlink, stale_ts_entry)
end
local stale_ts_parser = vim.fs.joinpath(data_dir, "lazy", "nvim-treesitter", "parser")
if vim.uv.fs_stat(stale_ts_parser) then
  pcall(vim.fn.delete, stale_ts_parser, "rf")
end

-- 3. Backwards compatibility shims for legacy nvim-treesitter modules in package.preload.
-- In nvim-treesitter main branch, several legacy submodules were removed or renamed.
-- These shims prevent errors when plugins or stale files attempt to require legacy paths.
if not package.preload["nvim-treesitter.configs"] then
  package.preload["nvim-treesitter.configs"] = function()
    local ok, config = pcall(require, "nvim-treesitter.config")
    if ok then
      return config
    end
    return {
      setup = function() end,
      get_module = function() return {} end,
      is_installed = function() return true end,
      commands = {},
    }
  end
end

if not package.preload["nvim-treesitter.query_predicates"] then
  package.preload["nvim-treesitter.query_predicates"] = function()
    return {}
  end
end

if not package.preload["nvim-treesitter.compat"] then
  package.preload["nvim-treesitter.compat"] = function()
    return {
      get_query_files = function(lang, query_name)
        return vim.treesitter.query.get_files(lang, query_name)
      end,
    }
  end
end

if not package.preload["nvim-treesitter.utils"] then
  package.preload["nvim-treesitter.utils"] = function()
    local ok, util = pcall(require, "nvim-treesitter.util")
    if ok then
      return util
    end
    return {
      setup_commands = function() end,
    }
  end
end

if not package.preload["nvim-treesitter.info"] then
  package.preload["nvim-treesitter.info"] = function()
    return { commands = {} }
  end
end

if not package.preload["nvim-treesitter.statusline"] then
  package.preload["nvim-treesitter.statusline"] = function()
    return {
      statusline = function() return "" end,
    }
  end
end

-- 4. Fallback loader for backwards/forwards compatibility between nvim-treesitter.textobjects.* and nvim-treesitter-textobjects.*
-- In nvim-treesitter-textobjects main branch, submodules are named nvim-treesitter-textobjects.<submod>
-- while on master branch they were nvim-treesitter.textobjects.<submod>.
-- Using a fallback loader in package.loaders ensures that disk modules are found first without being shadowed,
-- while smoothly resolving whichever naming convention the installed plugin version uses.
local resolving = {}
table.insert(package.loaders, function(modname)
  if resolving[modname] then
    return nil
  end
  local alt_mod
  if modname:match("^nvim%-treesitter%.textobjects%.") then
    alt_mod = modname:gsub("^nvim%-treesitter%.textobjects%.", "nvim-treesitter-textobjects.")
  elseif modname:match("^nvim%-treesitter%-textobjects%.") then
    alt_mod = modname:gsub("^nvim%-treesitter%-textobjects%.", "nvim-treesitter.textobjects.")
  end

  if alt_mod then
    resolving[modname] = true
    local ok, res = pcall(require, alt_mod)
    resolving[modname] = nil
    if ok and type(res) == "table" then
      return function()
        return res
      end
    end
  end
  return nil
end)

-- 5. Backwards compatibility shims for mason-lspconfig v2.0+ refactor.
-- In mason-lspconfig v2.0, mason-lspconfig.mappings.server and mason-lspconfig.mappings.filetype
-- were centralized into mason-lspconfig.mappings. These shims prevent errors when plugins
-- or older code require the legacy submodules.
if not package.preload["mason-lspconfig.mappings.server"] then
  package.preload["mason-lspconfig.mappings.server"] = function()
    local ok, mappings = pcall(require, "mason-lspconfig.mappings")
    if ok and mappings.get_mason_map then
      return mappings.get_mason_map()
    end
    return {
      package_to_lspconfig = {},
      lspconfig_to_package = {},
    }
  end
end

if not package.preload["mason-lspconfig.mappings.filetype"] then
  package.preload["mason-lspconfig.mappings.filetype"] = function()
    local ok, mappings = pcall(require, "mason-lspconfig.mappings")
    if ok and mappings.get_filetype_map then
      return mappings.get_filetype_map()
    end
    return {}
  end
end

return M

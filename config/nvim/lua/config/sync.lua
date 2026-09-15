return function(action)
  local ok, err = pcall(function()
    assert(vim.v.errmsg == "", "Neovim startup failed: " .. vim.v.errmsg)
    require("lazy")[action]({ wait = true, show = false })
    local failed = {}
    for name, plugin in pairs(require("lazy.core.config").plugins) do
      if (plugin.url and not plugin._.installed) or require("lazy.core.plugin").has_errors(plugin) then
        failed[#failed + 1] = name
      end
    end
    assert(#failed == 0, "Plugin installation failed: " .. table.concat(failed, ", "))
  end)
  if not ok then
    vim.api.nvim_err_writeln(tostring(err))
    return vim.cmd("cquit 1")
  end
  vim.cmd("qa")
end

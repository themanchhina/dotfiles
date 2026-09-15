local root = vim.env.TEST_ROOT or vim.fn.getcwd()
local scenario = vim.env.TEST_SYNC_SCENARIO
local plugin = { url = "https://example.invalid/plugin", _ = { installed = scenario ~= "missing" } }

package.preload.lazy = function()
  return {
    restore = function(options)
      assert(options.wait == true)
      if scenario == "task" then error("task failed") end
    end,
  }
end
package.preload["lazy.core.config"] = function() return { plugins = { example = plugin } } end
package.preload["lazy.core.plugin"] = function()
  return { has_errors = function() return scenario == "error" end }
end
package.path = root .. "/config/nvim/lua/?.lua;" .. package.path
require("config.sync")("restore")

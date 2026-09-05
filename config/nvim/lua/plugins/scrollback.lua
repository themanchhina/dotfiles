return {
  {
    "m00qek/baleia.nvim",
    cmd = { "BaleiaColorize", "BaleiaLogs" },
    opts = {
      line_starts_at = 1,
    },
    config = function(_, opts)
      vim.g.baleia = require("baleia").setup(opts)

      vim.api.nvim_create_user_command("BaleiaColorize", function()
        vim.g.baleia.once(vim.api.nvim_get_current_buf())
      end, { desc = "Colorize ANSI color escape codes in current buffer" })
    end,
  },
}

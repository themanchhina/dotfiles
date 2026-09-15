return {
  {
    "iamcco/markdown-preview.nvim",
    init = function()
      if vim.fn.has("mac") == 1 then
        return
      end

      -- ponytail: one preview server per host; use distinct ports if concurrent editors need previews.
      vim.g.mkdp_port = "8765"
      vim.g.mkdp_open_to_the_world = 0
      vim.g.mkdp_open_ip = "127.0.0.1"
      vim.g.mkdp_echo_preview_url = 1
      vim.g.mkdp_browserfunc = "DotfilesMarkdownPreview"
      vim.cmd([[
        function! DotfilesMarkdownPreview(url) abort
          call v:lua.DotfilesMarkdownPreview(a:url)
        endfunction
      ]])
      _G.DotfilesMarkdownPreview = function(url)
        local directory = vim.fn.expand("~/.cache/dotfiles")
        vim.fn.mkdir(directory, "p")
        -- Append notifications: tail cannot detect a same-length overwrite.
        vim.fn.writefile({ url }, directory .. "/markdown-preview.url", "a")
        vim.notify("Preview: " .. url .. " (run remote-preview <host> on your Mac)")
      end
    end,
  },
}

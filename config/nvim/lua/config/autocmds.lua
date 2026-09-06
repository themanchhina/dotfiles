-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`

-- Herdr & Terminal Scrollback Viewer
-- Triggered when opening temporary scrollback files dumped by Herdr (Cmd+Shift+E)
-- or any file matching *herdr-scrollback*.txt or *scrollback*.log
local function setup_scrollback_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  if vim.b[bufnr].scrollback_setup_done then return end
  vim.b[bufnr].scrollback_setup_done = true

  -- Ensure buffer is modifiable before colorizing / stripping ANSI escape codes
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].readonly = false

  -- Colorize ANSI escape codes synchronously
  local rendered = false
  if vim.g.baleia then
    local ok = pcall(vim.g.baleia.once, bufnr)
    if ok then rendered = true end
  else
    local ok, baleia = pcall(require, "baleia")
    if ok and baleia then
      local instance = baleia.setup({ line_starts_at = 1, async = false })
      local render_ok = pcall(instance.once, bufnr)
      if render_ok then rendered = true end
    end
  end

  if not rendered then
    -- Fast native Lua fallback: strip raw ANSI escape codes and carriage returns
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local modified = false
    for i, line in ipairs(lines) do
      local clean = line:gsub("\27%[[0-9;?]*[a-zA-Z]", ""):gsub("\27%][^\7\27]*[\7\27\\]", ""):gsub("\r", "")
      if clean ~= line then
        lines[i] = clean
        modified = true
      end
    end
    if modified then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    end
  end

  -- Buffer ergonomics for read-only inspection (only after rendering completes)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true

  -- Window ergonomics: iterate only windows displaying this specific buffer
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    vim.wo[win].wrap = false
    vim.wo[win].number = true
    vim.wo[win].relativenumber = false
    vim.wo[win].cursorline = true
    if line_count > 0 then
      vim.api.nvim_win_set_cursor(win, { line_count, 0 })
      vim.api.nvim_win_call(win, function()
        vim.cmd("normal! zz")
      end)
    end
  end

  -- Instant exit with 'q'
  vim.keymap.set("n", "q", "<cmd>quit!<cr>", {
    buffer = bufnr,
    silent = true,
    nowait = true,
    desc = "Quit scrollback viewer",
  })
end

local scrollback_group = vim.api.nvim_create_augroup("HerdrScrollback", { clear = true })

vim.api.nvim_create_autocmd({ "BufReadPost", "BufEnter" }, {
  group = scrollback_group,
  pattern = { "*herdr-scrollback*.txt", "*herdr-scrollback*", "*scrollback*.log" },
  callback = function(ev)
    -- Run on next tick to ensure buffer is fully loaded
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(ev.buf) then
        setup_scrollback_buffer(ev.buf)
      end
    end)
  end,
})

-- User command to manually apply scrollback formatting to current buffer
vim.api.nvim_create_user_command("ScrollbackMode", function()
  setup_scrollback_buffer()
end, { desc = "Format current buffer as a terminal scrollback viewer" })

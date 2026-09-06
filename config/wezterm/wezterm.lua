local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder()

config.color_scheme = "Tokyo Night Moon"
config.font = wezterm.font("MesloLGS NF")
config.font_size = 15.0
config.hide_tab_bar_if_only_one_tab = true
config.adjust_window_size_when_changing_font_size = false
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

-- Appearance & terminal ergonomics
config.audible_bell = "Disabled"
config.scrollback_lines = 10000
-- "RESIZE" hides the macOS title bar and traffic-light buttons completely (frameless).
-- If you prefer the full native title bar instead, change this to "TITLE | RESIZE".
config.window_decorations = "RESIZE"
config.window_padding = {
  left = 10,
  right = 10,
  top = 10,
  bottom = 10,
}
config.default_cursor_style = "BlinkingBlock"
config.cursor_blink_rate = 500

-- Browser & Link Opening
-- Shift+Click opens links in default browser (local and remote).
-- Shift+Drag bypasses Herdr/remote sessions for native WezTerm selection.
config.bypass_mouse_reporting_modifiers = "SHIFT"

config.keys = {
  -- Word hopping: Option + j (backward word) and Option + k (forward word)
  {
    key = "j",
    mods = "OPT",
    action = act.SendString("\x1bb"),
  },
  {
    key = "k",
    mods = "OPT",
    action = act.SendString("\x1bf"),
  },
  -- Standard Option + Left/Right arrows for word hopping
  {
    key = "LeftArrow",
    mods = "OPT",
    action = act.SendString("\x1bb"),
  },
  {
    key = "RightArrow",
    mods = "OPT",
    action = act.SendString("\x1bf"),
  },
  -- Cmd + k to clear scrollback and viewport
  {
    key = "k",
    mods = "CMD",
    action = act.Multiple({
      act.ClearScrollback("ScrollbackAndViewport"),
      act.SendKey({ key = "L", mods = "CTRL" }),
    }),
  },
  -- Cmd + c to copy selection to clipboard
  {
    key = "c",
    mods = "CMD",
    action = act.CopyTo("Clipboard"),
  },
  -- Cmd + v to paste from clipboard
  {
    key = "v",
    mods = "CMD",
    action = act.PasteFrom("Clipboard"),
  },
  -- Cmd + Shift + v sends Ctrl+V to Herdr (triggering remote image clipboard bridge)
  {
    key = "v",
    mods = "CMD|SHIFT",
    action = act.SendKey({ key = "v", mods = "CTRL" }),
  },
  -- Shift + Enter for newline across all harnesses (Claude, Codex, Agy)
  -- Sends Esc + Enter (\x1b\r), universally parsed as Alt/Option+Enter (newline without submit)
  {
    key = "Enter",
    mods = "SHIFT",
    action = act.SendString("\x1b\r"),
  },

  -- --------------------------------------------------------------------------
  -- Herdr Dedicated Shortcuts (Cmd + Shift) - Single shortcuts per action
  -- --------------------------------------------------------------------------
  -- Pane Cycling: adjacent pair (j = previous pane, k = next pane)
  {
    key = "j",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02j"),
  },
  {
    key = "k",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02k"),
  },

  -- Pane Splits (d = vertical split, s = horizontal split)
  {
    key = "d",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02v"),
  },
  {
    key = "s",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02-"),
  },

  -- Zoom focused pane (z = toggle full-screen)
  {
    key = "z",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02z"),
  },

  -- Tab Navigation: adjacent pair (u = previous tab, i = next tab, t = new tab)
  {
    key = "u",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02p"),
  },
  {
    key = "i",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02n"),
  },
  {
    key = "t",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02c"),
  },

  -- Close Pane (w = close)
  {
    key = "w",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02x"),
  },

  -- AI Agent Navigation: adjacent pair (p = previous agent, n = next agent)
  {
    key = "p",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02A"),
  },
  {
    key = "n",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02a"),
  },

  -- Sidebar toggle (b = toggle sidebar)
  {
    key = "b",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02b"),
  },

  -- Open scrollback in Neovim (e = edit scrollback)
  {
    key = "e",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02e"),
  },

  -- Quick Goto / Jump Palette (o = goto anything)
  {
    key = "o",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02g"),
  },

  -- New Git Worktree (g = new worktree + workspace)
  {
    key = "g",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02G"),
  },

  -- Lazygit floating modal popup (l = lazygit popup)
  {
    key = "l",
    mods = "CMD|SHIFT",
    action = act.SendString("\x02l"),
  },

  -- --------------------------------------------------------------------------
  -- Lifecycle & Renaming Shortcuts (Cmd + Option)
  -- --------------------------------------------------------------------------
  -- Workspace Switcher / Picker modal (Cmd + Option + O)
  {
    key = "o",
    mods = "CMD|OPT",
    action = act.SendString("\x02w"),
  },
  -- New Workspace (Cmd + Option + N)
  {
    key = "n",
    mods = "CMD|OPT",
    action = act.SendString("\x02N"),
  },
  -- Close Workspace (Cmd + Option + D)
  {
    key = "d",
    mods = "CMD|OPT",
    action = act.SendString("\x02D"),
  },
  -- Open Existing Worktree (Cmd + Option + G)
  {
    key = "g",
    mods = "CMD|OPT",
    action = act.SendString("\x02\x1bg"),
  },
  -- Close Tab (Cmd + Option + X)
  {
    key = "x",
    mods = "CMD|OPT",
    action = act.SendString("\x02X"),
  },
  -- Rename Pane / Agent (Cmd + Option + P or Cmd + Option + R)
  {
    key = "p",
    mods = "CMD|OPT",
    action = act.SendString("\x02P"),
  },
  {
    key = "r",
    mods = "CMD|OPT",
    action = act.SendString("\x02R"),
  },
  -- Rename Tab (Cmd + Option + T)
  {
    key = "t",
    mods = "CMD|OPT",
    action = act.SendString("\x02T"),
  },
  -- Rename Workspace (Cmd + Option + W)
  {
    key = "w",
    mods = "CMD|OPT",
    action = act.SendString("\x02W"),
  },
}

return config

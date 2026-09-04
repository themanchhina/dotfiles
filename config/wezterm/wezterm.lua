local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder()

config.color_scheme = "Tokyo Night Moon"
config.font = wezterm.font("MesloLGS NF")
config.font_size = 15.0
config.hide_tab_bar_if_only_one_tab = true
config.adjust_window_size_when_changing_font_size = false

-- Hold Shift to select text with the mouse (even inside apps like Neovim, Tmux, Lazygit)
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
  -- Word selection: Shift + Option + j (backward) and Shift + Option + k (forward)
  {
    key = "j",
    mods = "SHIFT|OPT",
    action = act.SendString("\x1b[1;4D"),
  },
  {
    key = "k",
    mods = "SHIFT|OPT",
    action = act.SendString("\x1b[1;4C"),
  },
  {
    key = "LeftArrow",
    mods = "SHIFT|OPT",
    action = act.SendString("\x1b[1;4D"),
  },
  {
    key = "RightArrow",
    mods = "SHIFT|OPT",
    action = act.SendString("\x1b[1;4C"),
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
}

config.key_tables = {
  copy_mode = {
    { key = "j", mods = "OPT", action = act.CopyMode("MoveBackwardWord") },
    { key = "k", mods = "OPT", action = act.CopyMode("MoveForwardWord") },
    { key = "j", mods = "SHIFT|OPT", action = act.CopyMode("MoveBackwardWord") },
    { key = "k", mods = "SHIFT|OPT", action = act.CopyMode("MoveForwardWord") },
  },
}

return config

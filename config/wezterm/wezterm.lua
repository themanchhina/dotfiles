local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder()

config.color_scheme = "Tokyo Night Moon"
config.font = wezterm.font("MesloLGS NF")
config.font_size = 15.0
config.hide_tab_bar_if_only_one_tab = true
config.adjust_window_size_when_changing_font_size = false

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
}

return config

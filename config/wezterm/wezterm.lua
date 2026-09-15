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

-- Shift+Drag bypasses remote mouse reporting for native WezTerm selection.
config.bypass_mouse_reporting_modifiers = "SHIFT"

-- Cmd-click opens links even when the app owns mouse reporting.
config.mouse_bindings = {
  {
    event = { Down = { streak = 1, button = "Left" } },
    mods = "CMD",
    mouse_reporting = true,
    action = act.Nop,
  },
  {
    event = { Up = { streak = 1, button = "Left" } },
    mods = "CMD",
    mouse_reporting = true,
    action = act.OpenLinkAtMouseCursor,
  },
}

-- Unsent outside Herdr, where \x02D would delete to end of line in Neovim.
local herdr_hosts = {
  herdr = true,
  ["herdr-client"] = true,
}

local function herdr(suffix, prefix)
  return wezterm.action_callback(function(window, pane)
    local proc = pane:get_foreground_process_name() or ""
    local name = proc:match("([^/]+)$") or proc
    if herdr_hosts[name] then
      window:perform_action(act.SendString((prefix or "\x02") .. suffix), pane)
    else
      window:toast_notification("WezTerm", "Not a Herdr session -- shortcut ignored", nil, 2000)
    end
  end)
end

config.keys = {
  -- Option+j/k stays unbound: LazyVim needs <A-j>/<A-k> for move-line.
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
  -- Cmd + k clears WezTerm's scrollback, not Herdr's; Herdr exposes no clear action.
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
  -- Cmd + Shift + v sends Alt + Ctrl+V (\x1b\x16), Herdr's direct remote-image shortcut.
  {
    key = "v",
    mods = "CMD|SHIFT",
    action = herdr("\x16", "\x1b"),
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
    action = herdr("j"),
  },
  {
    key = "k",
    mods = "CMD|SHIFT",
    action = herdr("k"),
  },

  -- Pane Splits (d = vertical split, s = horizontal split)
  {
    key = "d",
    mods = "CMD|SHIFT",
    action = herdr("v"),
  },
  {
    key = "s",
    mods = "CMD|SHIFT",
    action = herdr("-"),
  },

  -- Zoom focused pane (z = toggle full-screen)
  {
    key = "z",
    mods = "CMD|SHIFT",
    action = herdr("z"),
  },

  -- Tab Navigation: adjacent pair (u = previous tab, i = next tab, t = new tab)
  {
    key = "u",
    mods = "CMD|SHIFT",
    action = herdr("p"),
  },
  {
    key = "i",
    mods = "CMD|SHIFT",
    action = herdr("n"),
  },
  {
    key = "t",
    mods = "CMD|SHIFT",
    action = herdr("c"),
  },

  -- Close Pane (w = close)
  {
    key = "w",
    mods = "CMD|SHIFT",
    action = herdr("x"),
  },

  -- AI Agent Navigation: adjacent pair (p = previous agent, n = next agent)
  {
    key = "p",
    mods = "CMD|SHIFT",
    action = herdr("A"),
  },
  {
    key = "n",
    mods = "CMD|SHIFT",
    action = herdr("a"),
  },

  -- Sidebar toggle (b = toggle sidebar)
  {
    key = "b",
    mods = "CMD|SHIFT",
    action = herdr("b"),
  },

  -- Open scrollback in Neovim (e = edit scrollback)
  {
    key = "e",
    mods = "CMD|SHIFT",
    action = herdr("e"),
  },

  -- Quick Goto / Jump Palette (o = goto anything)
  {
    key = "o",
    mods = "CMD|SHIFT",
    action = herdr("g"),
  },

  -- New Git Worktree (g = new worktree + workspace)
  {
    key = "g",
    mods = "CMD|SHIFT",
    action = herdr("G"),
  },

  -- Lazygit floating modal popup (l = lazygit popup)
  {
    key = "l",
    mods = "CMD|SHIFT",
    action = herdr("l"),
  },

  -- --------------------------------------------------------------------------
  -- Lifecycle & Renaming Shortcuts (Cmd + Option)
  -- --------------------------------------------------------------------------
  -- Workspace Switcher / Picker modal (Cmd + Option + O)
  {
    key = "o",
    mods = "CMD|OPT",
    action = herdr("w"),
  },
  -- New Workspace (Cmd + Option + N)
  {
    key = "n",
    mods = "CMD|OPT",
    action = herdr("N"),
  },
  -- Close Workspace (Cmd + Option + D)
  {
    key = "d",
    mods = "CMD|OPT",
    action = herdr("D"),
  },
  -- Open Existing Worktree (Cmd + Option + G)
  {
    key = "g",
    mods = "CMD|OPT",
    action = herdr("\x1bg"),
  },
  -- Close Tab (Cmd + Option + X)
  {
    key = "x",
    mods = "CMD|OPT",
    action = herdr("X"),
  },
  -- Rename Pane / Agent (Cmd + Option + P or Cmd + Option + R)
  {
    key = "p",
    mods = "CMD|OPT",
    action = herdr("P"),
  },
  {
    key = "r",
    mods = "CMD|OPT",
    action = herdr("R"),
  },
  -- Rename Tab (Cmd + Option + T)
  {
    key = "t",
    mods = "CMD|OPT",
    action = herdr("T"),
  },
  -- Rename Workspace (Cmd + Option + W)
  {
    key = "w",
    mods = "CMD|OPT",
    action = herdr("W"),
  },
}

return config

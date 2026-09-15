local root = vim.env.TEST_ROOT or vim.fn.getcwd()
local sent, toasts = {}, {}
local action = {
  Nop = { name = "Nop" },
  OpenLinkAtMouseCursor = { name = "OpenLinkAtMouseCursor" },
}

for _, name in ipairs({ "ClearScrollback", "CopyTo", "Multiple", "PasteFrom", "SendKey", "SendString" }) do
  action[name] = function(value) return { name = name, value = value } end
end

package.preload.wezterm = function()
  return {
    action = action,
    action_callback = function(callback) return { name = "Callback", callback = callback } end,
    config_builder = function() return {} end,
    font = function(name) return name end,
  }
end

local config = dofile(root .. "/config/wezterm/wezterm.lua")
local function key(key, mods)
  for _, binding in ipairs(config.keys) do
    if binding.key == key and binding.mods == mods then return binding.action end
  end
  error("missing key: " .. mods .. "+" .. key)
end

local image = key("v", "CMD|SHIFT")

local close_workspace = key("d", "CMD|OPT")
local window = {
  perform_action = function(_, value) table.insert(sent, value.value) end,
  toast_notification = function(_, _, message) table.insert(toasts, message) end,
}
local function pane(process)
  return { get_foreground_process_name = function() return process end }
end

close_workspace.callback(window, pane("/opt/homebrew/bin/herdr"))
assert(sent[1] == "\x02D", "known Herdr foreground must receive the shortcut")
close_workspace.callback(window, pane("/usr/bin/ssh"))
close_workspace.callback(window, pane("/usr/local/bin/mosh-client"))
assert(#sent == 1 and #toasts == 2, "generic remote shells must not receive Herdr shortcuts")
image.callback(window, pane("/opt/homebrew/bin/herdr"))
assert(sent[2] == "\x1b\x16", "Cmd-Shift-v must send direct Alt-Ctrl-v")
image.callback(window, pane("/usr/bin/ssh"))
assert(#sent == 2, "image chord must also stay out of ordinary SSH sessions")

assert(config.bypass_mouse_reporting_modifiers == "SHIFT", "Shift drag bypass was lost")
assert(config.mouse_bindings[1].action == action.Nop and config.mouse_bindings[2].action == action.OpenLinkAtMouseCursor,
  "Cmd-click mouse bindings are incomplete")
assert(config.mouse_bindings[1].mouse_reporting and config.mouse_bindings[2].mouse_reporting,
  "Cmd-click must override app mouse reporting")

local herdr_config = table.concat(vim.fn.readfile(root .. "/config/herdr/config.toml"), "\n")
assert(herdr_config:find('remote_image_paste = "ctrl+alt+v"', 1, true), "remote image binding is invalid")
assert(not herdr_config:find("prefix+ctrl+v", 1, true), "prefixed special-key binding remains")
assert(not herdr_config:find('"prefix+s"', 1, true), "redundant horizontal split remains")
for direction, letter in pairs({ left = "h", down = "j", up = "k", right = "l" }) do
  assert(herdr_config:find('focus_pane_' .. direction .. ' = "ctrl+alt+' .. letter .. '"', 1, true),
    "missing directional pane binding: " .. direction)
end

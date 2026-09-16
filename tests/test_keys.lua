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

local window = {
  perform_action = function(_, value) table.insert(sent, value.value) end,
  toast_notification = function(_, _, message) table.insert(toasts, message) end,
}
local function pane(process)
  return { get_foreground_process_name = function() return process end }
end

assert(config.bypass_mouse_reporting_modifiers == "SHIFT", "Shift drag bypass was lost")
assert(config.mouse_bindings[1].action == action.Nop and config.mouse_bindings[2].action == action.OpenLinkAtMouseCursor,
  "Cmd-click mouse bindings are incomplete")
assert(config.mouse_bindings[1].mouse_reporting and config.mouse_bindings[2].mouse_reporting,
  "Cmd-click must override app mouse reporting")

local herdr_lines = vim.fn.readfile(root .. "/config/herdr/config.toml")
local herdr_config = table.concat(herdr_lines, "\n")
local herdr_bindings = {}
for _, line in ipairs(herdr_lines) do
  local name, value = line:match('^([%w_]+)%s*=%s*(.+)$')
  if name then herdr_bindings[name] = value end
end
local wrappers = {
  { "v", "CMD|SHIFT", "remote_image_paste", "ctrl+alt+v" },
  { "j", "CMD|SHIFT", "cycle_pane_previous", "prefix+j" },
  { "k", "CMD|SHIFT", "cycle_pane_next", "prefix+k" },
  { "d", "CMD|SHIFT", "split_vertical", "prefix+v" },
  { "s", "CMD|SHIFT", "split_horizontal", "prefix+-" },
  { "z", "CMD|SHIFT", "zoom", "prefix+z" },
  { "u", "CMD|SHIFT", "previous_tab", "prefix+p" },
  { "i", "CMD|SHIFT", "next_tab", "prefix+n" },
  { "t", "CMD|SHIFT", "new_tab", "prefix+c" },
  { "w", "CMD|SHIFT", "close_pane", "prefix+x" },
  { "p", "CMD|SHIFT", "previous_agent", "prefix+A" },
  { "n", "CMD|SHIFT", "next_agent", "prefix+a" },
  { "b", "CMD|SHIFT", "toggle_sidebar", "prefix+b" },
  { "e", "CMD|SHIFT", "edit_scrollback", "prefix+e" },
  { "o", "CMD|SHIFT", "goto", "prefix+g" },
  { "g", "CMD|SHIFT", "new_worktree", "prefix+G" },
  { "l", "CMD|SHIFT", "key", "prefix+l" },
  { "o", "CMD|OPT", "workspace_picker", "prefix+w" },
  { "n", "CMD|OPT", "new_workspace", "prefix+N" },
  { "d", "CMD|OPT", "close_workspace", "prefix+D" },
  { "g", "CMD|OPT", "open_worktree", "prefix+alt+g" },
  { "x", "CMD|OPT", "close_tab", "prefix+X" },
  { "p", "CMD|OPT", "rename_pane", "prefix+P" },
  { "r", "CMD|OPT", "rename_pane", "prefix+R" },
  { "t", "CMD|OPT", "rename_tab", "prefix+T" },
  { "w", "CMD|OPT", "rename_workspace", "prefix+W" },
}

for _, wrapper in ipairs(wrappers) do
  local wez_key, mods, herdr_key, herdr_binding = unpack(wrapper)
  local configured = herdr_bindings[herdr_key] or ""
  assert(configured:find('"' .. herdr_binding .. '"', 1, true), "missing Herdr binding: " .. herdr_key)
  local action = key(wez_key, mods)
  local before = #sent
  action.callback(window, pane("/opt/homebrew/bin/herdr"))
  local sequence = herdr_binding == "ctrl+alt+v" and "\x1b\x16"
    or "\x02" .. herdr_binding:gsub("^prefix%+", ""):gsub("^alt%+", "\x1b")
  assert(sent[before + 1] == sequence, mods .. "+" .. wez_key .. " does not match " .. herdr_binding)
end

local close_workspace = key("d", "CMD|OPT")
close_workspace.callback(window, pane("/usr/bin/ssh"))
close_workspace.callback(window, pane("/usr/local/bin/mosh-client"))
assert(#sent == #wrappers and #toasts == 2, "generic remote shells must not receive Herdr shortcuts")
key("v", "CMD|SHIFT").callback(window, pane("/usr/bin/ssh"))
assert(#sent == #wrappers, "image chord must also stay out of ordinary SSH sessions")

assert(not herdr_config:find("prefix+ctrl+v", 1, true), "prefixed special-key binding remains")
assert(not herdr_config:find('"prefix+s"', 1, true), "redundant horizontal split remains")
for direction, letter in pairs({ left = "h", down = "j", up = "k", right = "l" }) do
  assert(herdr_config:find('focus_pane_' .. direction .. ' = "ctrl+alt+' .. letter .. '"', 1, true),
    "missing directional pane binding: " .. direction)
end

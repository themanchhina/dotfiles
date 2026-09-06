-- Load compatibility shims before lazy.nvim to intercept early module requires
require("config.compat")

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

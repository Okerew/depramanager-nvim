# depramanager-nvim
Depramanager port for nvim

### Requirements
* pip obviosly for python 
* nodejs for js obviously
* cargo-outdated and cargo audit (not so obvious now is it)
* golang for go obviously
* composer for php also not so obvious

### Features

**Vulnerability scanning**

**See outdated pacakges**

**Automatic highlighting of outdaded depedencies in these files (requirements.txt, package.json, go.mod)**

Note: you must wait a bit if there are a lot of packages.

### Installation:
Any plugin manager should do the job but here is an example with vim plug
```vim
Plug 'rcarriga/nvim-notify'
Plug 'nvim-telescope/telescope.nvim'
Plug 'Okerew/depramanager-nvim'
```

### Setup:

You can setup depramanager like here

```lua
local depramanager = require('depramanager')

-- Enable auto-highlighting
depramanager.setup()

-- Optional
-- depramanager.check_all()
-- depramanager.clear_all_highlights()
-- depramanager.refresh_cache()
-- depramanager.status()

-- === KEYBINDS ===
-- Bind telescope functions to keys
vim.keymap.set('n', '<leader>dp', depramanager.python_telescope, { desc = 'Outdated Python packages' })
vim.keymap.set('n', '<leader>dg', depramanager.go_telescope, { desc = 'Outdated Go modules' })
vim.keymap.set('n', '<leader>dn', depramanager.npm_telescope, { desc = 'Outdated npm packages' })
vim.keymap.set('n', '<leader>dph', depramanager.php_telescope, { desc = 'Outdated php packages' })
vim.keymap.set('n', '<leader>dr', depramanager.rust_telescope, { desc = 'Outdated rust packages' })
vim.keymap.set('n', '<leader>dvp', depramanager.python_vulnerabilities_telescope, { desc = 'Outdated Python packages' })
vim.keymap.set('n', '<leader>dvg', depramanager.go_vulnerabilities_telescope, { desc = 'Outdated Go modules' })
vim.keymap.set('n', '<leader>dvn', depramanager.npm_vulnerabilities_telescope, { desc = 'Outdated npm packages' })
vim.keymap.set('n', '<leader>dvph', depramanager.php_vulnerabilities_telescope, { desc = 'Outdated php packages' })
vim.keymap.set('n', '<leader>dvr', depramanager.rust_vulnerabilities_telescope, { desc = 'Outdated rust packages' })
```

If using vim plug you need to add lua << EOF blocks.

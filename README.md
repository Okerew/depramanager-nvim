# depramanager-nvim
Depramanager port for nvim

### Installation:
Any plugin manager should do the job but here is an example with vim plug
```vim
Plug 'Okerew/depramanager-nvim'
```

### Setup:

You can setup depramanager like here

```lua
local depramanager = require('depramanager')

-- Enable auto-highlighting
depramanager.setup()

-- Bind telescope functions to keys
vim.keymap.set('n', '<leader>dp', depramanager.python_telescope, { desc = 'Outdated Python packages' })
vim.keymap.set('n', '<leader>dg', depramanager.go_telescope, { desc = 'Outdated Go modules' })
vim.keymap.set('n', '<leader>dn', depramanager.npm_telescope, { desc = 'Outdated npm packages' })
vim.keymap.set('n', '<leader>dvp', depramanager.python_vulnerabilities_telescope, { desc = 'Outdated Python packages' })
vim.keymap.set('n', '<leader>dvg', depramanager.go_vulnerabilities_telescope, { desc = 'Outdated Go modules' })
vim.keymap.set('n', '<leader>dvn', depramanager.npm_vulnerabilities_telescope, { desc = 'Outdated npm packages' })
```

If using vim plug you need to add lua << EOF blocks.

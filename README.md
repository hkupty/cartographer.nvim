# Cartographer.nvim

Simplify project navigation within neovim.

## What's this?

This is a project navigation selector, 100% native to neovim.

To install it, add the following to your init.vim:

```viml

Plug 'vigemus/impromptu.nvim' " Dependency needed for providing the selection prompt
Plug 'vigemus/cartographer.nvim'

```

## How to use it?

It provides three lua commands:

- `cartographer.config(obj)`: Allows you to config cartographer.
For example, if you use `fd` instead of `find`, you can set the following up:

```lua
local cartographer = require("cartographer")

cartographer.config{
  project = {
    root = "/opt/code", -- your projects root folder
    search_command = "fd -t d -d 3 -H '\\.git$' -c never -x echo {//}"
  },
  files = {
    search_command = "fd -c never -t f"
  }
}
```

- `cartographer.project()`: Change the tabpage directory to the selected project.
- `cartographer.files([edit])`: Open the selected file for editing. By default, uses `edit`.

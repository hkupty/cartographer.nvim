# This project is being archived.

Sorry for the inconvenience, but it has became a burden to maintain that many plugins in the recent years and this one can be deprecated in favor of [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).

I strongly encourage you to make a switch, but if you want to continue using cartographer.nvim, feel free to fork it and keep it rolling.

# Cartographer.nvim

Simplify project navigation within neovim.

## Install

To install it, add the following to your init.vim:

```viml

Plug 'vigemus/impromptu.nvim' " Dependency needed for providing the selection prompt
Plug 'vigemus/cartographer.nvim'

```

## What's this?

Cartographer is the helper tool to allow you navigating through your project and finding your files fast.

If uses prompt interface provided by [impromptu.nvim](https://github.com/Vigemus/impromptu.nvim),
that opens a list of files and allows you to filter through to reach the file you are searching for.

It is completely written in lua and is designed to be a lightweight alternative to grep/fzf.

It currently supports four 'navigation' filters:

### Projects

By setting up the 'root' folder, where you store your projects, `cartographer.nvim` will find all git
directories you have underneath so you can select it. It will change current tabs cwd to match the one
of the project you selected.

### Files

Plain list of all files under current folder so you can search through.
You can give it a parameter specifying how do you want to open the file,
so you can replace the current buffer or open in a vertical/horizontal split.

### Regular Expressions

You supply it a regular expression and it will display all lines/files that contain it, so you can land right at the match.

### TODO

As a convenience default to regular expressions, `cartographer.nvim` provides a navigation to all TODO/FIXME found on the project.

## Differences from fzf

It is a bit unfair to put `cartographer.nvim` as a direct proponent against `fzf` as `fzf` provides fuzzy-finding in a general context
and cartographer is focused on providing project navigation.

Nonetheless, based on my experience of trying to write cartographer for `fzf` before ([fzf-proj.nvim](https://github.com/Vigemus/fzf-proj.nvim)),
I can state the following differences:

* No external dependencies/setup needed (other than `find`/`grep` as sources of data);
* No `$PATH` issues;
* Easy to config and extend;

As cartographer and [impromptu.nvim](https://github.com/Vigemus/impromptu.nvim) are new projects, some features would be lacking when comparing to fzf (though in the backlog):

* Negative searching/filtering out
* Fuzzy searching

## How to use it?

It provides three lua commands:

- `cartographer.config(obj)`: Allows you to config cartographer.
For example, if you use `fd` instead of `find` and `rg` instead of `grep`, you can set the following up:

```lua
local cartographer = require("cartographer")

cartographer.config{
  project = {
    root = "/opt/code", -- your projects root folder
    search_command = "fd -t d -d 3 -H '\\.git$' -c never -x echo {//}"
  },
  files = {
    search_command = "fd -c never -t f"
  },
  rx = {
    search_command = "rg --vimgrep --color never"
  }
}
```

- `cartographer.project()`: Change the tabpage directory to the selected project.
- `cartographer.files([edit])`: Open the selected file for editing. By default, uses `edit`.
- `cartographer.rx(regex, [edit])`: Filter all files to select the ones where the `regex` matches. By default, uses `edit`.
- `cartographer.todo([edit])`: Open the file containing that `TODO` or `FIXME`. By default, uses `edit`.

Since that is a lua command, you can map it as you please:

```viml
nmap <C-M-p> <Cmd>lua require("cartographer").project()<CR>
nmap <C-p> <Cmd>lua require("cartographer").files()<CR>
nmap <C-v> <Cmd>lua require("cartographer").files("leftabove vnew")<CR>
nmap <C-h> <Cmd>lua require("cartographer").files("rightbelow new")<CR>
```

And also invoke it from functions:

```viml
:call luaeval('require("cartographer").rx(_A)', 'my-regex')<CR>
```

### Navigating throught the filter screen

The filter buffer, as provided by [impromptu.nvim](https://github.com/Vigemus/impromptu.nvim), gives you the following mappings:

* Insert Mode:
  * `<C-j>`: Down one item;
  * `<C-k>`: Up one item;
  * `<C-C>`: Abort;
  * `<CR>`: Select;

* Normal Mode:
  * `j`: Down one item;
  * `k`: Up one item;
  * `<C-C>`: Abort;
  * `<CR>`: Select;

Note that it doesn't stay on normal mode, as it is expected to be used solely on inser mode.

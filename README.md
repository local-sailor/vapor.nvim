# Vapor.nvim

<div align="centre">
<img src="Public/vapor.dash.demo.jpg " width="420"   alt="Makima_Mommy">
</div>

Vapor lets you jump between files and directories instanenousy through oil. 
Vapor is a fixed-slot navigation for Neovim: pin a file or directory once, then
jump back to it instantly with `Option+1` through `Option+9`. 

I realised very late that it's very similar to Harpoon, with three deliberate
differences:

- slots never reorder, so their numbers become muscle memory;
- directories are first-class favorites and open in Oil;
- opening a favorite scopes Telescope to the relevant directory or Git root.

## Features

- Nine persistent file or directory slots by default.
- Direct Option-number navigation in Warp and Meta-aware terminals.
- Oil integration for directory favorites, with a built-in fallback.
- Telescope file search rooted at any favorite.
- Snacks dashboard items with file and directory icons.
- Existing `favorites.json` files remain compatible.

## Installation

With lazy.nvim from a local checkout:

```lua
{
    dir = "/absolute/path/to/Vapor",
    name = "vapor.nvim",
    lazy = false,
    dependencies = {
        "stevearc/oil.nvim",
        "nvim-telescope/telescope.nvim",
    },
    opts = {},
}
```

From a Git repository after Vapor is published:

```lua
{
    "local-sailor/vapor.nvim",
    dependencies = {
        "stevearc/oil.nvim",
        "nvim-telescope/telescope.nvim",
    },
    opts = {},
}
```

Oil and Telescope are optional. Vapor falls back to Neovim's directory buffer
when Oil is unavailable, and only `:VaporFind` requires Telescope.

## Commands

| Command | Action |
| --- | --- |
| `:VaporAdd` | Pin the current file in the first free slot. |
| `:VaporAdd 3` | Pin the current file in slot 3. |
| `:VaporAdd! 3` | Pin the current working directory in slot 3. |
| `:VaporDelete 3` | Clear slot 3. |
| `:VaporList` | Display all slots. |
| `:VaporFind 3` | Open Telescope at slot 3's directory or Git root. |
| `:VaporFind` | Open Telescope at the current working directory. |

The old `:Fav`, `:FavDel`, and `:FavList` commands remain available by default
for compatibility.

## Configuration

```lua
require("vapor").setup({
    slots = 9,
    storage_path = vim.fn.stdpath("config") .. "/favorites.json",
    map_slots = true,
    legacy_commands = true,
})
```

To show Vapor in a Snacks dashboard section:

```lua
{
    icon = "󰓎 ",
    title = "Vapor",
    indent = 2,
    padding = 1,
    require("vapor").dashboard_items,
}
```

## Data format

Vapor stores an object keyed by slot number so empty slots never collapse:

```json
{
  "1": { "path": "/path/to/project", "kind": "dir" },
  "3": { "path": "/path/to/project/README.md", "kind": "file" }
}
```

Run `:help vapor` after installation for the compact reference.

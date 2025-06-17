# changesets.nvim

Fork of [bennypowers/changesets.nvim](https://github.com/bennypowers/changesets.nvim)

Easily create [changesets][cs] using your favourite editor.

<figure>

[screencast][screencast]

  <figcaption>

Screencast showing how to use changesets.nvim to:

1. pick package(s) from your project repo
2. pick a release type (`patch`, `minor`, or `major`)
3. pick a file name (trivial)
4. write your changeset
5. Add any other packages to the changeset

  </figcaption>
</figure>

## 🛌 Installation (Lazy)

```lua
return { 'sudo-tee/changesets.nvim',
  dependencies = { 'nvim-telescope/telescope.nvim', 'folke/snacks.nvim' }, -- choose only one for multiselect

  ---@module 'changesets'
  ---@type changesets.Opts
  opts = {
    changeset_dir = '.changesets',
  },
  keys = {
    { '<leader>cxx',
      function() require'changesets'.create() end,
      mode = 'n',
      desc = 'Create a changeset',
    },
    { '<leader>cxa',
      function() require'changesets'.add_package() end,
      mode = 'n',
      desc = 'Add a package to the changeset in the current buffer',
    },
  },
}
```

## ⚙️ Configuration

The following options can be set when calling setup or in your opts table:

```lua
require('changesets').setup({
  -- Root directory of your project (default: current working directory)
  cwd = vim.fn.getcwd(),

  -- Directory where changesets are stored (default: '.changesets')
  changeset_dir = '.changesets',

  -- Marker shown next to changed packages (default: '~')
  changed_packages_marker = '~',

  -- Highlight group for changed packages (default: 'Added')
  changed_packages_highlight = 'Added',

  -- Function that returns default text for new changesets (default: returns empty string)
  get_default_text = function()
    return ''
  end,

  -- List of known monorepo files (default: {'pnpm-workspace.yaml', 'lerna.json', 'turbo.json', 'nx.json', 'rush.json'})
  monorepo_files = { 'pnpm-workspace.yaml', 'lerna.json', 'turbo.json', 'nx.json', 'rush.json' },
})
```

[cs]: https://github.com/changesets/changesets
[screencast]: https://github.com/bennypowers/changesets.nvim/assets/1466420/ac1e670a-9be9-4177-99d7-8ae7033c2822

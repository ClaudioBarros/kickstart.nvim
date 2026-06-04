vim.pack.add { { src = 'https://github.com/stevearc/oil.nvim' } }

require('oil').setup {
  default_file_explorer = true, -- replace netrw
  delete_to_trash = true,
  skip_confirm_for_simple_edits = true,
  view_options = {
    show_hidden = true,
  },
  keymaps = {
    ['q'] = { 'actions.close', mode = 'n' },
  },
}

vim.keymap.set('n', '<leader>o', '<cmd>Oil<cr>', { desc = 'Open parent directory (oil)' })
vim.keymap.set('n', '<leader>e', function() require('oil').toggle_float() end, { desc = 'Toggle oil (floating)' })

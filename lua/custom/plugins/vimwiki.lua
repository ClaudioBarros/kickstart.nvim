vim.pack.add { { src = 'https://github.com/vimwiki/vimwiki' } }

vim.cmd 'filetype plugin on'
vim.cmd 'syntax on'

vim.g.vimwiki_list = {
  {
    path = '~/vimwiki/',
    syntax = 'markdown',
    ext = '.md',
  },
}

vim.g.vimwiki_global_ext = 0 -- don't claim every .md file as vimwiki
vim.g.vimwiki_markdown_link_ext = 1 -- keep .md extension in generated links

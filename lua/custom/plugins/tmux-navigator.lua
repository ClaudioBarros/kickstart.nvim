-- Maps <C-h/j/k/l> to switch vim splits in the given direction. If there are
-- no more windows in that direction, forwards the operation to tmux.
-- Additionally, <C-\> toggles between last active vim splits/tmux panes.

local M = {}

local pane_position_from_direction = {
  h = 'left',
  j = 'bottom',
  k = 'top',
  l = 'right',
}

local direction_translation = {
  p = 'l',
  h = 'L',
  j = 'D',
  k = 'U',
  l = 'R',
}

local tmux_is_last_pane = false

local function get_opt(name, default)
  local ok, val = pcall(function() return vim.g[name] end)
  if not ok or val == nil then
    return default
  end
  return val
end

local function tmux_or_tmate_executable()
  local tmux = vim.env.TMUX or ''
  if tmux:find('tmate') then
    return 'tmate'
  end
  return 'tmux'
end

local function tmux_socket()
  local tmux = vim.env.TMUX or ''
  return vim.split(tmux, ',', { plain = true })[1]
end

local function tmux_command(args)
  local cmd = tmux_or_tmate_executable() .. ' -S ' .. tmux_socket() .. ' ' .. args
  local saved = vim.o.shellcmdflag
  vim.o.shellcmdflag = '-c'
  local result = vim.fn.system(cmd)
  vim.o.shellcmdflag = saved
  return result
end

local function tmux_vim_pane_is_zoomed()
  local out = tmux_command("display-message -p '#{window_zoomed_flag}'")
  return tonumber(vim.trim(out)) == 1
end

local function vim_navigate(direction)
  local ok, err = pcall(vim.cmd, 'wincmd ' .. direction)
  if not ok then
    vim.api.nvim_echo(
      { { 'E11: Invalid in command-line window; <CR> executes, CTRL-C quits: wincmd k', 'ErrorMsg' } },
      false, {}
    )
    local _ = err
  end
end

local function needs_vitality_redraw()
  -- Modern Neovim does not need the vitality workaround.
  return false
end

local function should_forward_navigation_back_to_tmux(last_pane, at_tab_page_edge)
  if get_opt('tmux_navigator_disable_when_zoomed', 0) == 1 and tmux_vim_pane_is_zoomed() then
    return false
  end
  return last_pane or at_tab_page_edge
end

local function save_on_switch()
  local mode = get_opt('tmux_navigator_save_on_switch', 0)
  if mode == 1 then
    pcall(vim.cmd, 'update')
  elseif mode == 2 then
    pcall(vim.cmd, 'wall')
  end
end

local function tmux_aware_navigate(direction)
  local nr = vim.fn.winnr()
  local last_pane = (direction == 'p' and tmux_is_last_pane)
  if not last_pane then
    vim_navigate(direction)
  end
  local at_tab_page_edge = (nr == vim.fn.winnr())

  if should_forward_navigation_back_to_tmux(last_pane, at_tab_page_edge) then
    save_on_switch()

    local target = vim.fn.shellescape(vim.env.TMUX_PANE or '')
    local args = 'select-pane -t ' .. target .. ' -' .. direction_translation[direction]

    if get_opt('tmux_navigator_preserve_zoom', 0) == 1 then
      args = args .. ' -Z'
    end

    if get_opt('tmux_navigator_no_wrap', 0) == 1 and direction ~= 'p' then
      args = 'if -F "#{pane_at_' .. pane_position_from_direction[direction] .. '}" "" "' .. args .. '"'
    end

    pcall(tmux_command, args)
    if needs_vitality_redraw() then
      vim.cmd('redraw!')
    end
    tmux_is_last_pane = true
  else
    tmux_is_last_pane = false
  end
end

local function tmux_navigator_process_list()
  print(tmux_command("run-shell 'ps -o state= -o comm= -t ''''#{pane_tty}'''''"))
end

-- Public entry points -------------------------------------------------------

function M.navigate(direction)
  if vim.env.TMUX == nil or vim.env.TMUX == '' then
    vim_navigate(direction)
  else
    tmux_aware_navigate(direction)
  end
end

function M.left()      M.navigate('h') end
function M.down()      M.navigate('j') end
function M.up()        M.navigate('k') end
function M.right()     M.navigate('l') end
function M.previous()  M.navigate('p') end

function M.process_list()
  tmux_navigator_process_list()
end

local function is_fzf()
  return vim.bo.filetype == 'fzf'
end

function M.setup()
  if vim.g.loaded_tmux_navigator == 1 then
    return
  end
  vim.g.loaded_tmux_navigator = 1

  -- User commands
  vim.api.nvim_create_user_command('TmuxNavigateLeft',     function() M.left()     end, {})
  vim.api.nvim_create_user_command('TmuxNavigateDown',     function() M.down()     end, {})
  vim.api.nvim_create_user_command('TmuxNavigateUp',       function() M.up()       end, {})
  vim.api.nvim_create_user_command('TmuxNavigateRight',    function() M.right()    end, {})
  vim.api.nvim_create_user_command('TmuxNavigatePrevious', function() M.previous() end, {})
  vim.api.nvim_create_user_command('TmuxNavigatorProcessList', function() M.process_list() end, {})

  -- Track window enters to reset the "last pane" flag.
  local group = vim.api.nvim_create_augroup('tmux_navigator', { clear = true })
  vim.api.nvim_create_autocmd('WinEnter', {
    group = group,
    callback = function() tmux_is_last_pane = false end,
  })

  if get_opt('tmux_navigator_no_mappings', 0) == 1 then
    return
  end

  local opts = { silent = true, noremap = true }
  vim.keymap.set('n', '<C-h>',  '<Cmd>TmuxNavigateLeft<CR>',     opts)
  vim.keymap.set('n', '<C-j>',  '<Cmd>TmuxNavigateDown<CR>',     opts)
  vim.keymap.set('n', '<C-k>',  '<Cmd>TmuxNavigateUp<CR>',       opts)
  vim.keymap.set('n', '<C-l>',  '<Cmd>TmuxNavigateRight<CR>',    opts)
  vim.keymap.set('n', '<C-\\>', '<Cmd>TmuxNavigatePrevious<CR>', opts)

  if vim.env.TMUX and vim.env.TMUX ~= '' then
    local function term_map(lhs, fallback, cmd)
      vim.keymap.set('t', lhs, function()
        if is_fzf() then
          return fallback
        end
        return '<C-\\><C-n>:' .. cmd .. '<CR>'
      end, { silent = true, expr = true, replace_keycodes = true })
    end
    term_map('<C-h>', '<C-h>', 'TmuxNavigateLeft')
    term_map('<C-j>', '<C-j>', 'TmuxNavigateDown')
    term_map('<C-k>', '<C-k>', 'TmuxNavigateUp')
    term_map('<C-l>', '<C-l>', 'TmuxNavigateRight')
  end

  if get_opt('tmux_navigator_disable_netrw_workaround', 0) ~= 1 then
    if vim.g.Netrw_UserMaps == nil then
      vim.g.Netrw_UserMaps = { { '<C-l>', '<Cmd>TmuxNavigateRight<CR>' } }
    else
      vim.api.nvim_echo({ {
        'vim-tmux-navigator conflicts with netrw <C-l> mapping. '
        .. 'See https://github.com/christoomey/vim-tmux-navigator#netrw or set '
        .. '`vim.g.tmux_navigator_disable_netrw_workaround = 1` to suppress this warning.',
        'ErrorMsg',
      } }, true, {})
    end
  end
end

return M

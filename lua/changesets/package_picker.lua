local config = require('changesets.opts')
local u = require('changesets.utils')

local M = {}

local function get_best_picker()
  local prefered_picker = config.opts().prefered_picker
  if prefered_picker and prefered_picker ~= '' then
    return prefered_picker
  end

  return u.filter(function(plugin)
    return u.has_plugin(plugin) and true
  end, { 'snacks', 'telescope', 'fzf-lua', 'mini.pick' })[1] or nil
end

---@param package Package
local format_entry = function(package)
  local opts = config.opts()
  local hl = package.changed and opts.changed_packages_highlight or ''
  return {
    { package.changed and opts.changed_packages_marker or '', hl },
    { package.name, hl },
  }
end

---@param packages Package[]
---@param prompt string
---@param callback fun(selections: Package[])
local function telescope_ui(packages, prompt, callback)
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local entry_display = require('telescope.pickers.entry_display')
  local themes = require('telescope.themes')

  local displayer = entry_display.create({
    separator = ' ',
    items = {
      { width = #config.opts().changed_packages_marker },
      { remaining = true },
    },
  })

  local make_display = function(entry)
    return displayer(format_entry(entry.value))
  end

  pickers
    .new(themes.get_dropdown(), {
      prompt_title = prompt,
      finder = finders.new_table({
        results = packages,
        entry_maker = function(entry)
          return {
            value = entry,
            display = make_display,
            ordinal = entry.name,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(bufnr, map)
        actions.select_default:replace(function()
          local selections = action_state.get_current_picker(bufnr):get_multi_selection()

          if u.empty(selections) then
            selections = { action_state.get_selected_entry() }
          end

          actions.close(bufnr)

          callback(u.map(function(s)
            return s.value
          end, selections))
        end)

        local function select_all()
          local picker = action_state.get_current_picker(bufnr)
          for _, entry in ipairs(picker.finder.results) do
            picker._multi:add(entry)
          end

          picker:refresh()
        end

        map('i', '<C-a>', select_all)

        return true
      end,
    })
    :find()
end

---@param packages Package[]
---@param prompt string
---@param callback fun(selections: Package[])
local function fzf_ui(packages, prompt, callback)
  local fzf_lua = require('fzf-lua')
  local display_items = {}
  local lookup = {}

  for _, pkg in ipairs(packages) do
    local status = pkg.changed and config.opts().changed_packages_marker or ''
    local label = string.format('%s %s', status, pkg.name)
    display_items[#display_items + 1] = label
    lookup[label] = pkg
  end

  fzf_lua.fzf_exec(display_items, {
    prompt = prompt .. ' > ',
    multi = true,
    fzf_opts = { ['--multi'] = true },
    actions = {
      ['default'] = function(selected)
        if not selected or #selected == 0 then
          return
        end
        local results = vim.tbl_map(function(label)
          return lookup[label]
        end, selected)
        if callback then
          callback(results)
        end
      end,
    },
  })
end

---@param packages Package[]
---@param prompt string
---@param callback fun(selections: Package[])
local function mini_pick_ui(packages, prompt, callback)
  local mini_pick = require('mini.pick')
  local format_entry_mini = function(buf_id, pks, query, opts)
    local items = u.map(function(p)
      return (p.changed and config.opts().changed_packages_marker or '') .. p.name
    end, pks)
    return mini_pick.default_show(buf_id, items, query, opts)
  end

  mini_pick.start({
    mappings = {
      choose = '<M-CR>',
      choose_marked = '<CR>',
      mark = '<Tab>',
      toggle_preview = nil,
    },
    window = {
      prompt_prefix = prompt .. ' > ',
    },
    source = {
      preview = nil,
      show = format_entry_mini,
      items = packages,
      choose = function(item)
        if item and callback then
          callback({ item })
        end
        return false
      end,
      choose_marked = function(selected_items)
        if u.empty(selected_items) then
          vim.schedule(function()
            --- fallback to default behavior if no items selected
            vim.fn.feedkeys(vim.api.nvim_replace_termcodes('<M-CR>', true, false, true), 'n')
          end)
          return true
        end
        if selected_items and callback then
          callback(selected_items)
        end
        return false
      end,
    },
  })
end

---@param packages Package[]
---@param prompt string
---@param callback fun(selections: Package[])
local function snacks_picker_ui(packages, prompt, callback)
  ---@module 'snacks'
  ---@type snacks.picker.Item[]
  local items = u.map(function(package)
    return { text = package.name, item = package }
  end, packages)

  local layout = Snacks.picker.config.layout('select')
  layout.preview = { enabled = false }
  layout.layout.title = ' ' .. prompt .. ' '
  Snacks.picker.pick({
    items = items,
    layout = layout,
    format = function(item)
      return format_entry(item.item)
    end,
    confirm = function(picker, _)
      local selected = picker:selected({ fallback = true })
      picker:close()
      if callback and selected then
        callback(u.map(function(s)
          return s.item
        end, selected))
      end
    end,
  })
end

---@param packages Package[]
---@param prompt string
---@param callback fun(selections: Package[])
local function basic_ui(packages, prompt, callback)
  local items = u.map(function(package)
    return { text = (package.changed and config.opts().changed_packages_marker or '') .. package.name, package }
  end, packages)

  vim.ui.select(items, {
    prompt = 'Select a package',
    format_item = function(item)
      return item.text
    end,
  }, function(selected)
    if selected and callback then
      callback({ selected })
    end
  end)
end

---@param packages Package[]
---@param prompt string
---@param callback fun(selections: Package[])
function M.pick(packages, prompt, callback)
  local picker = get_best_picker()
  local wrapped_callback = vim.schedule_wrap(callback)

  vim.schedule(function()
    if picker == 'telescope' then
      telescope_ui(packages, prompt, wrapped_callback)
    elseif picker == 'fzf' then
      fzf_ui(packages, prompt, wrapped_callback)
    elseif picker == 'mini.pick' then
      mini_pick_ui(packages, prompt, wrapped_callback)
    elseif picker == 'snacks' then
      snacks_picker_ui(packages, prompt, wrapped_callback)
    else
      vim.notify('No suitable picker found.\n Falling back to vim.ui.select', vim.log.levels.WARN)
      basic_ui(packages, prompt, wrapped_callback)
    end
  end)
end

return M

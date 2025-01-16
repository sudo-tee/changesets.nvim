local config = require('changesets.opts')
local u = require('changesets.utils')
local git = require('changesets.git')

local M = {}

---Check if a plugin is available
---@param plugin string The plugin name to check
---@return boolean true if plugin is available
local function has_plugin(plugin)
  return pcall(require, plugin)
end

---@alias Operation 'add'|'create'

---@class Package
---@field name string
---@field path string
---@field changed boolean
---

M.changed_files_cache = {}

---Extract package name from package.json file
---@param path string Path to package.json file
---@return string Package name or empty string if not found
local function get_package_name(path)
  local lines = vim.fn.readfile(path)
  local content = vim.fn.json_decode(table.concat(lines))

  return content and content.name or ''
end

local function find_all_package_jsons()
  return u.map(function(path)
    return u.joinpath(config.opts().cwd, path)
  end, git.find_files("'package.json' '**/package.json'"))
end

local format_package_name = function(package)
  local opts = config.opts()
  local hl = package.changed and opts.changed_packages_highlight or ''
  return {
    { package.changed and opts.changed_packages_marker or '', hl },
    { package.name, hl },
  }
end

local function select_packages_with_snacks_picker(packages, prompt, format_entry, callback)
  ---@module 'snacks'
  ---@type snacks.picker.Item[]
  local items = {}
  for idx, package in ipairs(packages) do
    table.insert(items, {
      item = package,
      idx = idx,
    })
  end

  local layout = Snacks.picker.config.layout('select')
  layout.preview = false
  layout.layout.title = ' ' .. prompt .. ' '
  Snacks.picker.pick({
    items = items,
    source = 'select',
    layout = layout,
    format = function(item)
      return format_entry(item.item)
    end,
    confirm = function(picker, _)
      local selected = picker:selected({ fallback = true })
      callback(u.map(function(s)
        return s.item
      end, selected))
    end,
  })
end

---Prompts the user to select or more packages from a list of packages
---@param items Package[]
---@param prompt string
---@param format_entry fun(package: Package): string[]
---@param callback fun(selections: Package[])
local function select_packages_with_telescope(items, prompt, format_entry, callback)
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
        results = items,
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

        local function select_all_changed()
          local picker = action_state.get_current_picker(bufnr)
          for _, entry in ipairs(picker.finder.results) do
            if entry.value.changed then
              picker._multi:add(entry)
            end
          end

          picker:refresh()
        end

        map('i', '<C-a>', select_all_changed)

        return true
      end,
    })
    :find()
end

---Writes a changeset with the given contents and name
---@param lines string[] the contents of the changeset
local function on_enter_name(lines)
  return function(filename)
    if not filename then
      return
    end

    local filepath = u.joinpath(config.opts().changeset_dir, filename .. '.md')
    vim.cmd('e ' .. filepath)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { #lines, 0 })
    vim.cmd('startinsert')
  end
end

---@param name string package name
---@param type Release release type
---@return string release changeset package release line
local function format(name, type)
  return '"' .. name .. '": ' .. type
end

local function select_changeset_name(package_list)
  vim.ui.input(
    {
      prompt = 'Enter changeset name',
      default = require('changesets.random').humanId(),
    },
    on_enter_name(u.flatten({
      '---',
      package_list,
      '---',
      '',
      config.opts().get_default_text(),
    }))
  )
end

local function update_current_changeset(package_list)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
  local header_end_line = u.find_last_occurrence(lines, '---')

  table.insert(lines, header_end_line, package_list)

  vim.api.nvim_buf_set_lines(0, 0, -1, true, u.flatten(lines))
end

local function get_packages_from_current_changeset()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
  local header_end_line = u.find_last_occurrence(lines, '---')
  local packages_lines = {}

  for i = 2, header_end_line - 1 do
    table.insert(packages_lines, lines[i])
  end

  return u.map(function(line)
    return line:match('"(.-)":')
  end, packages_lines)
end

---Given the name of a package to change, and the type of a release to generate,
---Formats and writes a changeset with the user's preference of name.
---@param packages Package[]
---@param operation Operation
local function on_select_release(packages, operation)
  ---@param type Release
  return function(type)
    if not type then
      return
    end

    local package_list = u.map(function(package)
      return format(package.name, type)
    end, packages)

    if operation == 'create' then
      select_changeset_name(package_list)
    else
      update_current_changeset(package_list)
    end
  end
end

---Prompts the user to select a release type
---@param packages Package[]
---@param operation Operation
local function select_release_type(packages, operation)
  vim.ui.select(config.RELEASE_KINDS, {
    prompt = 'Select release type',
  }, on_select_release(packages, operation))
end

---Callback for when the user selects packages
---It prompts the user to select a release type
---@param operation Operation
local function on_select_packages(operation)
  ---@param packages Package[]
  return function(packages)
    if u.empty(packages) then
      return
    end

    select_release_type(packages, operation)
  end
end

local function path_is_changed(path)
  local folder = vim.fn.fnamemodify(path, ':h')
  return u.contains(M.changed_files_cache, u.start_with(folder))
end

---Sort packages by their changed status and name
---@param a Package First package to compare
---@param b Package Second package to compare
---@return boolean True if a should come before b
local function sort_by_changed(a, b)
  if a.changed == b.changed then
    return a.name < b.name
  end
  return a.changed
end

---Provides a list of all the npm package manifests
---found in the project directory.
---@return Package[]
local function get_workspace_packages()
  local packages = u.map(function(path)
    return { path = path, name = get_package_name(path), changed = path_is_changed(path) }
  end, find_all_package_jsons())

  table.sort(packages, sort_by_changed)

  return packages
end

---Get the packages that are in the workspace but not in the changeset
---@return Package[]
local function get_remaining_workspace_packages()
  local changeset_packages = get_packages_from_current_changeset()
  local workspace_packages = get_workspace_packages()

  return vim.tbl_filter(function(package)
    return not u.contains(changeset_packages, package.name)
  end, workspace_packages)
end

function M.validate_changeset_file()
  if vim.bo.filetype == 'markdown' and vim.fn.expand('%:p:h') == config.opts().changeset_dir then
    return true
  end

  print('Current buffer is a changeset')
  return false
end

---@param operation Operation
function M.make_operation(operation)
  local select = on_select_packages(operation)

  return function()
    M.changed_files_cache = git.get_changed_folders()

    local packages = {}
    if operation == 'add' and M.validate_changeset_file() then
      packages = get_remaining_workspace_packages()
    else
      packages = get_workspace_packages()
    end

    if u.empty(packages) then
      print('No packages found')
      return
    end

    local has_snacks, _ = has_plugin('snacks')
    local has_telescope, _ = has_plugin('telescope')

    if has_snacks then
      select_packages_with_snacks_picker(packages, 'Select Package - <Tab> multi | <C-a> all changed', format_package_name, select)
    elseif has_telescope then
      select_packages_with_telescope(packages, 'Select Package - <Tab> multi | <C-a> all changed', format_package_name, select)
    else
      print('Error: Neither telescope nor snacks plugin is installed')
      return
    end
  end
end

return M

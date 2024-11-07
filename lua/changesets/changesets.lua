local map = vim.tbl_map
local empty = vim.tbl_isempty
local config = require('changesets.opts')
local utils = require('changesets.utils')
local git = require('changesets.git')

local M = {}

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
  return map(function(path)
    return utils.joinpath(config.opts().cwd, path)
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

---Prompts the user to select or more packages from a list of packages
---@param items Package[]
---@param prompt string
---@param format_entry fun(package: Package): string[]
---@param callback fun(selections: Package[])
local function select_packages(items, prompt, format_entry, callback)
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
      { width = 1 },
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
      attach_mappings = function(bufnr)
        actions.select_default:replace(function()
          local selections = action_state.get_current_picker(bufnr):get_multi_selection()

          if empty(selections) then
            selections = { action_state.get_selected_entry() }
          end

          actions.close(bufnr)

          callback(map(function(s)
            return s.value
          end, selections))
        end)
        return true
      end,
    })
    :find()
end

---Writes a changeset with the given contents and name
---@param lines string[] the contents of the changeset
local function on_enter_name(lines)
  return function(filename)
    vim.cmd('e ' .. '.changeset/' .. filename .. '.md')
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
    on_enter_name(utils.flatten({
      '---',
      package_list,
      '---',
      '',
      '',
    }))
  )
end

local function update_current_changeset(package_list)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
  local header_end_line = utils.find_last_occurrence(lines, '---')

  table.insert(lines, header_end_line, package_list)

  vim.api.nvim_buf_set_lines(0, 0, -1, true, utils.flatten(lines))
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

    local package_list = map(function(package)
      return format(package.name, type)
    end, packages)

    if operation == 'create' then
      select_changeset_name(package_list)
    else
      update_current_changeset(package_list)
    end
  end
end

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
    if empty(packages) then
      return
    end

    select_release_type(packages, operation)
  end
end

local function path_is_changed(path)
  local folder = vim.fn.fnamemodify(path, ':h')
  return utils.contains(M.changed_files_cache, utils.start_with(folder))
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
  local packages = map(function(path)
    return { path = path, name = get_package_name(path), changed = path_is_changed(path) }
  end, find_all_package_jsons())

  table.sort(packages, sort_by_changed)

  return packages
end

---@param operation Operation
function M.make_operation(operation)
  local select = on_select_packages(operation)

  return function()
    M.changed_files_cache = git.get_changed_files()
    if operation == 'add' and vim.bo.filetype ~= 'markdown' then
      print('Current buffer is not a changeset')
      return
    end

    local packages = get_workspace_packages()
    if #packages == 1 then
      select(unpack(packages))
    else
      select_packages(packages, 'Select Package', format_package_name, select)
    end
  end
end

return M

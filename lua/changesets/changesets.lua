local config = require('changesets.opts')
local u = require('changesets.utils')
local git = require('changesets.git')

local M = {}

---@alias Operation 'add'|'create'

---@class Package
---@field name string
---@field path string
---@field changed boolean
---@field private boolean
---

M.changed_files_cache = {}

---Extract package name from package.json file
---@param path string Path to package.json file
---@return table Package content
local function get_package_content(path)
  local lines = vim.fn.readfile(path)
  local content = vim.fn.json_decode(table.concat(lines))

  return content
end

local function find_all_package_jsons()
  return u.map(function(path)
    return u.joinpath(config.opts().cwd, path)
  end, git.find_files("'package.json' '**/package.json'"))
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

---Check if the current project is a monorepo
---@return boolean True if the project is a monorepo
local function is_monorepo()
  local root = config.opts().cwd
  local root_package = u.joinpath(root, 'package.json')
  if get_package_content(root_package) and get_package_content(root_package).workspaces then
    return true
  end

  return u.contains(config.opts().monorepo_files, function(file)
    return u.file_exists(u.joinpath(root, file))
  end)
end

---Provides a list of all the npm package manifests
---found in the project directory.
---@return Package[]
local function get_workspace_packages()
  local package_jsons = find_all_package_jsons()

  if is_monorepo() then
    package_jsons = u.filter(function(path)
      return u.joinpath(config.opts().cwd, 'package.json') ~= path
    end, package_jsons)
  end

  local packages = u.map(function(path)
    local content = get_package_content(path)
    return { path = path, name = content.name, changed = path_is_changed(path), private = content.private }
  end, package_jsons)

  table.sort(packages, sort_by_changed)

  return config.opts().filter_packages and config.opts().filter_packages(packages) or packages
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

local function validate_changeset_file()
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
    if operation == 'add' and validate_changeset_file() then
      packages = get_remaining_workspace_packages()
    else
      packages = get_workspace_packages()
    end

    if u.empty(packages) then
      print('No packages found')
      return
    end

    local picker = require('changesets.package_picker')
    picker.pick(packages, 'Select Package(s) - <Tab> multi | <C-a> all', select)
  end
end

return M

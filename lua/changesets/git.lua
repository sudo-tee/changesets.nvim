local utils = require('changesets.utils')
local config = require('changesets.opts')

local M = {}

---Builds a git command with the proper working directory
---@param command string The git subcommand and arguments
---@return string The full git command
local function git_cmd(command)
  local cwd = config.opts().cwd
  return string.format('git -C %s %s', cwd, command)
end

---Get the default git branch (main or master)
---@return string
function M.default_git_branch()
  return vim.trim(vim.fn.system(git_cmd("branch -l main master --format '%(refname:short)'")))
end

---Get the list of files that changed between (main/master) and the current branches
---@return string[]
function M.get_changed_files()
  local cwd = config.opts().cwd
  local default_branch = M.default_git_branch()
  local files = vim.fn.systemlist(git_cmd('diff --name-only ' .. default_branch))

  local unique_folders = {}

  for _, file in ipairs(files) do
    local folder = utils.dirname(utils.joinpath(cwd, file))
    unique_folders[folder] = true
  end

  return vim.tbl_keys(unique_folders)
end

---Find files in git repository matching the given pattern
---@param pattern string Git ls-files pattern
---@return string[] List of matching file paths
function M.find_files(pattern)
  return vim.fn.systemlist(git_cmd(' ls-files  --full-name ' .. pattern))
end

return M

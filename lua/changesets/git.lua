local u = require('changesets.utils')
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

---Gets all folders containing files that changed between the default branch and current branch
---@return string[] List of changed folder paths, sorted by path length (most specific first)
function M.get_changed_folders()
  local cwd = config.opts().cwd
  local default_branch = M.default_git_branch()
  local changed_files = vim.fn.systemlist(git_cmd('diff --name-only ' .. default_branch))
  local uniq = {}
  local folders = {}

  for _, file in ipairs(changed_files) do
    local folder = u.dirname(u.joinpath(cwd, file))
    if not uniq[folder] then
      uniq[folder] = true
      table.insert(folders, folder)
    end
  end

  table.sort(folders, function(a, b)
    return #a > #b
  end)

  return folders
end

---Find files in git repository matching the given pattern
---@param pattern string Git ls-files pattern
---@return string[] List of matching file paths
function M.find_files(pattern)
  return vim.fn.systemlist(git_cmd(' ls-files  --full-name ' .. pattern))
end

return M

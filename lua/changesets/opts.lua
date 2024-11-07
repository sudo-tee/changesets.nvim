---@alias Release 'patch'|'minor'|'major'

local M = {}

---List of the kinds of releases that you can specify in a changeset
---@type Release[]
M.RELEASE_KINDS = { 'patch', 'minor', 'major' }

M.default_opts = {
  cwd = vim.fn.getcwd(),
  changeset_dir = '.changesets',
  changed_packages_marker = '~',
  changed_packages_highlight = 'TelescopeResultsConstant',
}

local _opts = vim.tbl_deep_extend('force', {}, M.default_opts)

M.setup = function(opts)
  _opts = vim.tbl_deep_extend('force', M.default_opts, opts)
end

M.opts = function()
  return _opts
end

return M

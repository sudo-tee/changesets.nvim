---@alias Release 'patch'|'minor'|'major'

local M = {}

---List of the kinds of releases that you can specify in a changeset
---@type Release[]
M.RELEASE_KINDS = { 'patch', 'minor', 'major' }

---@class changesets.Opts
---@field cwd string
---@field changeset_dir string
---@field changed_packages_marker string
---@field changed_packages_highlight string
---@field get_default_text fun(): string
---@field monorepo_files? string[]|nil

---@type changesets.Opts
M.default_opts = {
  cwd = vim.fn.getcwd(),
  changeset_dir = '.changeset',
  changed_packages_marker = '~',
  changed_packages_highlight = 'Added',
  get_default_text = function()
    return ''
  end,
  monorepo_files = { 'pnpm-workspace.yaml', 'lerna.json', 'turbo.json', 'nx.json', 'rush.json' },
}

---@type changesets.Opts
local _opts = vim.tbl_deep_extend('force', {}, M.default_opts)

---Setup the options for the plugin
---@param opts changesets.Opts
M.setup = function(opts)
  _opts = vim.tbl_deep_extend('force', M.default_opts, opts or {})
end

---Get the current options for the plugin
---@return changesets.Opts
M.opts = function()
  return _opts
end

return M

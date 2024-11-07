local Changesets = require('changesets.changesets')
local config = require('changesets.opts')

local M = {}

M.create = Changesets.make_operation('create')
M.add_package = Changesets.make_operation('add')
M.setup = config.setup

return M

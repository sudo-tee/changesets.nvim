local M = {}

---@param str string
function M.start_with(str)
  return function(line)
    return line:sub(1, #str) == str
  end
end

---@param tbl table
---@param predicate function
---@param opts? table
---@return boolean
function M.contains(tbl, predicate, opts)
  opts = opts or {}
  return vim.tbl_contains(tbl, predicate, vim.tbl_extend('force', opts, { predicate = true }))
end

function M.flatten(tbl)
  return vim.iter(tbl):flatten():totable()
end

---Find the last occurrence of a string in a table
---@param tbl table The table to search in
---@param str string The string to search for
---@return number|nil index of last occurrence or nil if not found
function M.find_last_occurrence(tbl, str)
  for i = #tbl, 1, -1 do
    if tbl[i] == str then
      return i
    end
  end
  return nil
end

function M.basename(str)
  local name = string.gsub(str, '(.*/)(.*)', '%2')
  return name
end

function M.dirname(str)
  local name = string.gsub(str, '(.*/)(.*)', '%1')
  return name
end

--- Concatenate directories and/or file into a single path with normalization
--- (e.g., `"foo/"` and `"bar"` get joined to `"foo/bar"`)
--- TODO: remove for >=0.10
---@param ... string
---@return string
M.joinpath = vim.fs.joinpath or function(...)
  return (table.concat({ ... }, '/'):gsub('//+', '/'))
end

M.map = vim.tbl_map

M.empty = vim.tbl_isempty

return M

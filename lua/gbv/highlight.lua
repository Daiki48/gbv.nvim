-- gbv.nvim: Highlight group definitions
local M = {}

-- Color palette for branch visualization
M.branch_colors = {
  "#e06c75", -- red
  "#98c379", -- green
  "#e5c07b", -- yellow
  "#61afef", -- blue
  "#c678dd", -- purple
  "#56b6c2", -- cyan
  "#d19a66", -- orange
  "#be5046", -- crimson
  "#7ec8e3", -- light blue
  "#c3e88d", -- lime
}

-- Highlight group name prefixes
M.graph_hl_prefix = "GbvGraph"
M.branch_hl_prefix = "GbvBranch"

local initialized = false

function M.setup()
  if initialized then
    return
  end
  initialized = true

  -- Prevent duplicate registration; redefine highlights on colorscheme change
  local augroup = vim.api.nvim_create_augroup("GbvHighlight", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup,
    callback = function()
      initialized = false
      M.setup()
    end,
  })

  -- Graph line highlights (color per branch)
  -- Use default = true to respect user's colorscheme settings
  for i, color in ipairs(M.branch_colors) do
    vim.api.nvim_set_hl(0, M.graph_hl_prefix .. i, { fg = color, bold = true, default = true })
  end

  -- Meta information highlights
  vim.api.nvim_set_hl(0, "GbvHash", { fg = "#e5c07b", bold = true, default = true })
  vim.api.nvim_set_hl(0, "GbvDate", { fg = "#56b6c2", default = true })
  vim.api.nvim_set_hl(0, "GbvAuthor", { fg = "#c678dd", default = true })
  vim.api.nvim_set_hl(0, "GbvMessage", { fg = "#abb2bf", default = true })
  vim.api.nvim_set_hl(0, "GbvBranchLabel", { fg = "#98c379", bold = true, default = true })
  vim.api.nvim_set_hl(0, "GbvMore", { fg = "#61afef", bold = true, default = true })

  -- Flow view highlights
  vim.api.nvim_set_hl(0, "GbvFlowTag", { fg = "#e5c07b", bold = true, default = true })
  vim.api.nvim_set_hl(0, "GbvFlowBranch", { fg = "#61afef", bold = true, default = true })
  vim.api.nvim_set_hl(0, "GbvFlowMerged", { fg = "#98c379", bold = true, default = true })
  vim.api.nvim_set_hl(0, "GbvFlowNotMerged", { fg = "#e06c75", bold = true, default = true })
  vim.api.nvim_set_hl(0, "GbvFlowLine", { fg = "#5c6370", default = true })
  vim.api.nvim_set_hl(0, "GbvFlowHeader", { fg = "#c678dd", bold = true, default = true })
  vim.api.nvim_set_hl(0, "GbvFlowHead", { fg = "#56b6c2", bold = true, default = true })

  -- Detail view highlights
  vim.api.nvim_set_hl(0, "GbvDetailHeader", { fg = "#61afef", bold = true, default = true })
  vim.api.nvim_set_hl(0, "GbvDetailLabel", { fg = "#c678dd", bold = true, default = true })
  vim.api.nvim_set_hl(0, "GbvDetailValue", { fg = "#abb2bf", default = true })
  vim.api.nvim_set_hl(0, "GbvFileAdded", { fg = "#98c379", bold = true, default = true })
  vim.api.nvim_set_hl(0, "GbvFileModified", { fg = "#e5c07b", bold = true, default = true })
  vim.api.nvim_set_hl(0, "GbvFileDeleted", { fg = "#e06c75", bold = true, default = true })
  vim.api.nvim_set_hl(0, "GbvDiffAdd", { fg = "#98c379", default = true })
  vim.api.nvim_set_hl(0, "GbvDiffDelete", { fg = "#e06c75", default = true })
  vim.api.nvim_set_hl(0, "GbvDiffHunk", { fg = "#61afef", bold = true, default = true })
end

--- Get highlight group name from branch index
---@param index number
---@return string
function M.get_graph_hl(index)
  local color_index = ((index - 1) % #M.branch_colors) + 1
  return M.graph_hl_prefix .. color_index
end

return M

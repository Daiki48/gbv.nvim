-- gbv.nvim: Git Branch Visualizer
-- A Neovim plugin that visualizes branches and commits with a colorful graph
local M = {}

local highlight = require("gbv.highlight")
local ui = require("gbv.ui")

--- Default configuration
---@type table
M.config = {
  -- Number of commits per page
  page_size = 200,
  -- Max display width for commit messages
  max_message_width = 50,
  -- Max diff lines to display (excess lines are truncated)
  max_diff_lines = 2000,
  -- Flow view settings
  flow = {
    -- Lua pattern to match release branch names
    release_branch_pattern = "^release",
    -- Main branch name (nil = auto-detect)
    main_branch = nil,
    -- Lua pattern to filter tags (nil = all tags)
    tag_pattern = nil,
  },
}

--- Configure the plugin
---@param opts table|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  ui.page_size = M.config.page_size
  ui.commit_limit = M.config.page_size
end

--- Open the plugin
function M.open()
  -- Initialize highlights
  highlight.setup()

  -- Show main view
  ui.open()
end

--- Open the flow view
function M.open_flow()
  highlight.setup()
  require("gbv.flow_ui").open()
end

return M

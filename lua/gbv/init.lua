-- gbv.nvim: Git Branch Visualizer
-- A Neovim plugin that visualizes branches and commits with a colorful graph
local M = {}

local highlight = require("gbv.highlight")
local ui = require("gbv.ui")

--- デフォルト設定
---@type table
M.config = {
  -- 1ページあたりのコミット数
  page_size = 200,
  -- コミットメッセージの最大表示幅
  max_message_width = 50,
  -- diff の最大表示行数（超過分は省略）
  max_diff_lines = 2000,
  -- フロービュー設定
  flow = {
    -- リリースブランチのパターン（Lua パターン）
    release_branch_pattern = "^release",
    -- メインブランチ名（nil なら自動検出）
    main_branch = nil,
    -- タグパターン（nil なら全タグ）
    tag_pattern = nil,
  },
}

--- プラグインの設定
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

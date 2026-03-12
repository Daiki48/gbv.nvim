-- gbv.nvim: Commit detail split view
local M = {}

local graph = require("gbv.graph")

-- Detail buffer/window state
M.detail_buf = nil
M.detail_win = nil

--- Return display string and highlight group for file status
---@param status string "A", "M", "D" etc.
---@return string label
---@return string hl_group
local function file_status_display(status)
  if status == "A" then
    return "[Added]", "GbvFileAdded"
  elseif status == "M" then
    return "[Modified]", "GbvFileModified"
  elseif status == "D" then
    return "[Deleted]", "GbvFileDeleted"
  elseif status == "R" then
    return "[Renamed]", "GbvFileModified"
  elseif status == "C" then
    return "[Copied]", "GbvFileAdded"
  else
    return "[" .. status .. "]", "GbvFileModified"
  end
end

--- Write content to the detail view buffer
---@param commit table commit data
---@param repo_root string
---@param main_win number|nil main window ID (defaults to current window)
---@param default_branch string|nil cached default branch name
function M.show(commit, repo_root, main_win, default_branch)
  if not commit or not commit.is_commit or not repo_root or repo_root == "" then
    return
  end

  -- Determine main window
  main_win = main_win or vim.api.nvim_get_current_win()

  -- Get detail information（キャッシュ済みdefault_branchを渡す）
  local detail = graph.get_commit_detail(repo_root, commit.hash, default_branch)

  -- Recreate buffer if invalid
  local need_new_buf = not M.detail_buf or not vim.api.nvim_buf_is_valid(M.detail_buf)
  if need_new_buf then
    M.detail_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.detail_buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = M.detail_buf })
    vim.api.nvim_set_option_value("buflisted", false, { buf = M.detail_buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = M.detail_buf })
    vim.api.nvim_set_option_value("filetype", "gbv-detail", { buf = M.detail_buf })

    -- Set q keymap once on buffer creation
    vim.keymap.set("n", "q", function()
      M.close()
    end, { noremap = true, silent = true, buffer = M.detail_buf })

    -- Clean up state when buffer is wiped
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = M.detail_buf,
      once = true,
      callback = function()
        M.detail_buf = nil
        M.detail_win = nil
      end,
    })
  end

  -- Create or reuse window
  if not M.detail_win or not vim.api.nvim_win_is_valid(M.detail_win) then
    -- Ensure main window is selected before splitting
    if vim.api.nvim_win_is_valid(main_win) then
      vim.api.nvim_set_current_win(main_win)
    end
    -- sbuffer で分割とバッファ設定を同時に行い、フリッカーを防止
    vim.cmd("botright vertical sbuffer " .. M.detail_buf)
    M.detail_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_option_value("number", false, { win = M.detail_win })
    vim.api.nvim_set_option_value("relativenumber", false, { win = M.detail_win })
    vim.api.nvim_set_option_value("signcolumn", "no", { win = M.detail_win })
    vim.api.nvim_set_option_value("wrap", false, { win = M.detail_win })
  else
    -- 既存ウィンドウにバッファを設定（バッファ再作成時の対応）
    vim.api.nvim_win_set_buf(M.detail_win, M.detail_buf)
  end

  -- Make buffer writable
  vim.api.nvim_set_option_value("modifiable", true, { buf = M.detail_buf })

  -- Build content
  local lines = {}
  local hl_marks = {} -- { line_idx, col_start, col_end, hl_group }

  -- Header
  lines[#lines + 1] = "━━━ Commit Details ━━━"
  hl_marks[#hl_marks + 1] = { #lines - 1, 0, -1, "GbvDetailHeader" }
  lines[#lines + 1] = ""

  -- Commit hash
  local hash_label = "Hash:     "
  lines[#lines + 1] = hash_label .. commit.hash
  hl_marks[#hl_marks + 1] = { #lines - 1, 0, #hash_label, "GbvDetailLabel" }
  hl_marks[#hl_marks + 1] = { #lines - 1, #hash_label, -1, "GbvHash" }

  -- Author
  local author_label = "Author:   "
  lines[#lines + 1] = author_label .. commit.author
  hl_marks[#hl_marks + 1] = { #lines - 1, 0, #author_label, "GbvDetailLabel" }
  hl_marks[#hl_marks + 1] = { #lines - 1, #author_label, -1, "GbvAuthor" }

  -- Date
  local date_label = "Date:     "
  lines[#lines + 1] = date_label .. commit.date
  hl_marks[#hl_marks + 1] = { #lines - 1, 0, #date_label, "GbvDetailLabel" }
  hl_marks[#hl_marks + 1] = { #lines - 1, #date_label, -1, "GbvDate" }

  -- Branches
  if #commit.branches > 0 then
    local branch_label = "Branches: "
    lines[#lines + 1] = branch_label .. table.concat(commit.branches, ", ")
    hl_marks[#hl_marks + 1] = { #lines - 1, 0, #branch_label, "GbvDetailLabel" }
    hl_marks[#hl_marks + 1] = { #lines - 1, #branch_label, -1, "GbvBranchLabel" }
  end

  local contained_label = "Contained in: "
  lines[#lines + 1] = contained_label
  hl_marks[#hl_marks + 1] = { #lines - 1, 0, #contained_label, "GbvDetailLabel" }
  if #(detail.contained_branches or {}) > 0 then
    for _, branch in ipairs(detail.contained_branches) do
      lines[#lines + 1] = "  " .. branch
      hl_marks[#hl_marks + 1] = { #lines - 1, 2, -1, "GbvBranchLabel" }
    end
  else
    lines[#lines + 1] = "  (No containing branches)"
  end

  local merge_status_label = "Merged into default branch: "
  local merge_status
  if detail.default_branch then
    if detail.merged_into_default then
      merge_status = "Yes (" .. detail.default_branch .. ")"
    else
      merge_status = "No (" .. detail.default_branch .. ")"
    end
  else
    merge_status = "Unknown"
  end
  lines[#lines + 1] = merge_status_label .. merge_status
  hl_marks[#hl_marks + 1] = { #lines - 1, 0, #merge_status_label, "GbvDetailLabel" }
  hl_marks[#hl_marks + 1] = { #lines - 1, #merge_status_label, -1, "GbvDetailValue" }

  lines[#lines + 1] = ""

  -- Commit message body
  lines[#lines + 1] = "━━━ Message ━━━"
  hl_marks[#hl_marks + 1] = { #lines - 1, 0, -1, "GbvDetailHeader" }
  lines[#lines + 1] = ""

  for _, body_line in ipairs(detail.body_lines or {}) do
    lines[#lines + 1] = body_line
    hl_marks[#hl_marks + 1] = { #lines - 1, 0, -1, "GbvMessage" }
  end

  lines[#lines + 1] = ""

  -- Changed files list
  lines[#lines + 1] = "━━━ Changed Files ━━━"
  hl_marks[#hl_marks + 1] = { #lines - 1, 0, -1, "GbvDetailHeader" }
  lines[#lines + 1] = ""

  for _, file in ipairs(detail.files or {}) do
    local label, hl = file_status_display(file.status)
    local file_line = "  " .. label .. " " .. file.path
    lines[#lines + 1] = file_line
    hl_marks[#hl_marks + 1] = { #lines - 1, 2, 2 + #label, hl }
  end

  if #(detail.files or {}) == 0 then
    lines[#lines + 1] = "  (No changed files)"
  end

  lines[#lines + 1] = ""

  -- Diff
  lines[#lines + 1] = "━━━ Diff ━━━"
  hl_marks[#hl_marks + 1] = { #lines - 1, 0, -1, "GbvDetailHeader" }
  lines[#lines + 1] = ""

  for _, diff_line in ipairs(detail.diff_lines or {}) do
    lines[#lines + 1] = diff_line
    local line_idx = #lines - 1
    if diff_line:match("^%+") and not diff_line:match("^%+%+%+") then
      hl_marks[#hl_marks + 1] = { line_idx, 0, -1, "GbvDiffAdd" }
    elseif diff_line:match("^%-") and not diff_line:match("^%-%-%-") then
      hl_marks[#hl_marks + 1] = { line_idx, 0, -1, "GbvDiffDelete" }
    elseif diff_line:match("^@@") then
      hl_marks[#hl_marks + 1] = { line_idx, 0, -1, "GbvDiffHunk" }
    end
  end

  -- Write to buffer
  vim.api.nvim_buf_set_lines(M.detail_buf, 0, -1, false, lines)

  -- Apply highlights (nvim_buf_add_highlight supports col_end=-1 for end of line)
  local ns = vim.api.nvim_create_namespace("gbv_detail")
  vim.api.nvim_buf_clear_namespace(M.detail_buf, ns, 0, -1)
  for _, mark in ipairs(hl_marks) do
    local row, col_start, col_end, hl_group = mark[1], mark[2], mark[3], mark[4]
    if row < #lines then
      pcall(vim.api.nvim_buf_add_highlight, M.detail_buf, ns, hl_group, row, col_start, col_end)
    end
  end

  -- Make read-only（nofile + modifiable=false で十分）
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.detail_buf })

  -- Move cursor to top
  if vim.api.nvim_win_is_valid(M.detail_win) then
    vim.api.nvim_win_set_cursor(M.detail_win, { 1, 0 })
  end

  -- Return focus to main window
  if vim.api.nvim_win_is_valid(main_win) then
    vim.api.nvim_set_current_win(main_win)
  end
end

--- Close the detail view
function M.close()
  if M.detail_win and vim.api.nvim_win_is_valid(M.detail_win) then
    vim.api.nvim_win_close(M.detail_win, true)
  end
  M.detail_win = nil
  M.detail_buf = nil
end

return M

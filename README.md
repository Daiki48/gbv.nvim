# gbv.nvim

**G**it **B**ranch **V**isualizer for Neovim. A plugin that displays git branches and commits as a colorful graph inside Neovim, with a split pane for viewing commit details, diffs, and changed files.

## Features

### `:GBV` — Commit Graph

- Colorful graph visualization of branches and commits (up to 10 distinct colors)
- Each line shows: graph, short hash, date, author, and commit message
- Branch labels displayed inline on the relevant commits
- Paginated commit list with a `[More commits...]` row for loading older history
- Opens in a dedicated tab; press Enter on any commit to open a detail view in a vertical split
- Detail view includes: full commit hash, author, date, branches, containing branches, merge status, full commit message, changed files (added/modified/deleted/renamed/copied), and diff

### `:GBVFlow` — Release Flow Matrix

- Tag × Branch matrix view showing which tags are merged into which branches
- Fixed header with branch names that stays visible while scrolling
- Visual markers: `●` merged, `○` not merged, `─` branch not yet existed, `◎` HEAD
- Color-coded cells (green = merged, red = not merged, grey = not existed)
- Press Enter on any tag row to view commit details in a side pane
- Useful for tracking release propagation across multiple branches

```
                    master    release1  release2  release3
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
v3.0  2024-03-01    ●         ●         ●         ●
v2.0  2024-02-01    ●         ●         ○         ─
v1.0  2024-01-01    ●         ●         ●         ─
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
HEAD                ◎         ◎         ◎         ◎
```

## Requirements

- Neovim >= 0.9
- Git

## Installation

```lua
-- lazy.nvim
{
  "Daiki48/gbv.nvim",
  cmd = { "GBV", "GBVFlow" },
  opts = {},
}
```

## Configuration

`setup()` is optional. Default values are shown below:

```lua
require("gbv").setup({
  -- Number of commits per page
  page_size = 200,
  -- Max display width for commit messages
  max_message_width = 50,
  -- Max diff lines to display (excess lines are truncated)
  max_diff_lines = 2000,
  -- Release flow matrix settings
  flow = {
    -- Lua pattern to match release branch names
    release_branch_pattern = "^release",
    -- Main branch name (nil = auto-detect)
    main_branch = nil,
    -- Lua pattern to filter tags (nil = all tags)
    tag_pattern = nil,
  },
})
```

## Usage

Open a terminal in any git repository and launch Neovim, then run:

```
:GBV
```

This opens the graph view in a new tab. Press `q` to close and return to the previous window.

```
:GBVFlow
```

This opens the release flow matrix view in a new tab with a fixed header.

### Keybindings

#### `:GBV` (Graph View)

| Key     | Action                                      |
|---------|---------------------------------------------|
| `Enter` | Open commit detail, or load more history    |
| `q`     | Close the graph view (or the detail pane)   |

#### `:GBVFlow` (Flow View)

| Key     | Action                                      |
|---------|---------------------------------------------|
| `Enter` | Open tag commit detail in a side pane       |
| `r`     | Refresh the matrix (rebuild DAG)            |
| `q`     | Close the flow view (or the detail pane)    |

Standard Vim motions (`j`/`k`, `gg`, `G`, etc.) work as expected in both views.

### Graph View

The main buffer displays a git log graph with the following columns:

```
graph  short_hash  date  author  message [branch_name]
```

### Flow View

The flow view displays a tag × branch matrix with a fixed header. The top window shows branch names and a separator line; the bottom window shows tag rows that can be scrolled with `j`/`k`.

The `flow.release_branch_pattern` setting controls which branches appear as columns. The main branch is always included as the first column.

### Detail View

When you press Enter on a commit (`:GBV`) or a tag row (`:GBVFlow`), a vertical split opens on the right showing:

- Full commit hash
- Author and date
- Branches at this commit
- Containing branches (all branches that include this commit)
- Merge status into the default branch
- Full commit message
- List of changed files with status (added / modified / deleted / renamed / copied)
- Diff with syntax highlighting for added and removed lines

## License

MIT

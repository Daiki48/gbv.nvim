# gbv.nvim

**G**it **B**ranch **V**isualizer for Neovim. A plugin that displays git branches and commits as a colorful graph inside Neovim, with a split pane for viewing commit details, diffs, and changed files.

## Features

- Colorful graph visualization of branches and commits (up to 10 distinct colors)
- Each line shows: graph, short hash, date, author, and commit message
- Branch labels displayed inline on the relevant commits
- Paginated commit list with a `[More commits...]` row for loading older history
- Opens in a dedicated tab; press Enter on any commit to open a detail view in a vertical split
- Detail view includes: full commit hash, author, date, branches, containing branches, merge status, full commit message, changed files (added/modified/deleted/renamed/copied), and diff

## Requirements

- Neovim >= 0.9
- Git

## Installation

```lua
-- lazy.nvim
{
  "Daiki48/gbv.nvim",
  cmd = { "GBV" },
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
})
```

## Usage

Open a terminal in any git repository and launch Neovim, then run:

```
:GBV
```

This opens the graph view in a new tab. Press `q` to close and return to the previous window.

### Keybindings

| Key     | Action                                      |
|---------|---------------------------------------------|
| `Enter` | Open commit detail, or load more history    |
| `q`     | Close the graph view (or the detail pane)   |

Standard Vim motions (`j`/`k`, `gg`, `G`, etc.) work as expected.

### Graph View

The main buffer displays a git log graph with the following columns:

```
graph  short_hash  date  author  message [branch_name]
```

### Detail View

When you press Enter on a commit, a vertical split opens on the right showing:

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

-- gbv.nvim: Git Branch Visualizer
-- Open branch/commit graph with :GBV command

vim.api.nvim_create_user_command("GBV", function()
  require("gbv").open()
end, { desc = "Open Git Branch Visualizer" })

vim.api.nvim_create_user_command("GBVFlow", function()
  require("gbv").open_flow()
end, { desc = "Open Git Release Flow Visualizer" })

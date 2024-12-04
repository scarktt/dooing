---------------------------------------------
--- Incredible feature developed by @derivia
---------------------------------------------

local M = {}

-- Dependencies
local state = require("dooing.state")

-- Export todos to a JSON file
function M.prompt_export()
	local default_path = vim.fn.expand("~/todos.json")

	vim.ui.input({
		prompt = "Export todos to file: ",
		default = default_path,
		completion = "file",
	}, function(file_path)
		if not file_path or file_path == "" then
			vim.notify("Export cancelled", vim.log.levels.INFO)
			return
		end

		-- expand ~ to full home directory path
		file_path = vim.fn.expand(file_path)

		local success, message = state.export_todos(file_path)
		if success then
			vim.notify(message, vim.log.levels.INFO)
		else
			vim.notify(message, vim.log.levels.ERROR)
		end
	end)
end

-- Import todos from a JSON file
function M.prompt_import(render_callback)
	local default_path = vim.fn.expand("~/todos.json")

	vim.ui.input({
		prompt = "Import todos from file: ",
		default = default_path,
		completion = "file",
	}, function(file_path)
		if not file_path or file_path == "" then
			vim.notify("Import cancelled", vim.log.levels.INFO)
			return
		end

		-- expand ~ to full home directory path
		file_path = vim.fn.expand(file_path)

		local success, message = state.import_todos(file_path)
		if success then
			vim.notify(message, vim.log.levels.INFO)
			if render_callback then
				render_callback()
			end
		else
			vim.notify(message, vim.log.levels.ERROR)
		end
	end)
end

return M

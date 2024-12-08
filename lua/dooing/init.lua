local M = {}
local config = require("dooing.config")
local ui = require("dooing.ui")
local state = require("dooing.state")

function M.setup(opts)
	config.setup(opts)
	state.load_todos()

	vim.api.nvim_create_user_command("Dooing", function(opts)
		local args = vim.split(opts.args, "%s+", { trimempty = true })
		if #args == 0 then
			ui.toggle_todo_window()
			return
		end

		local command = args[1]
		table.remove(args, 1) -- Remove command

		if command == "add" then
			-- Parse priorities if -p or --priorities flag is present
			local priorities = nil
			local todo_text = ""

			local i = 1
			while i <= #args do
				if args[i] == "-p" or args[i] == "--priorities" then
					if i + 1 <= #args then
						-- Get and validate priorities
						local priority_str = args[i + 1]
						local priority_list = vim.split(priority_str, ",", { trimempty = true })

						-- Validate each priority against config
						local valid_priorities = {}
						local invalid_priorities = {}
						for _, p in ipairs(priority_list) do
							local is_valid = false
							for _, config_p in ipairs(config.options.priorities) do
								if p == config_p.name then
									is_valid = true
									table.insert(valid_priorities, p)
									break
								end
							end
							if not is_valid then
								table.insert(invalid_priorities, p)
							end
						end

						-- Notify about invalid priorities
						if #invalid_priorities > 0 then
							vim.notify(
								"Invalid priorities: " .. table.concat(invalid_priorities, ", "),
								vim.log.levels.WARN,
								{ title = "Dooing" }
							)
						end

						if #valid_priorities > 0 then
							priorities = valid_priorities
						end

						i = i + 2 -- Skip priority flag and value
					else
						vim.notify("Missing priority value after " .. args[i], vim.log.levels.ERROR, {
							title = "Dooing",
						})
						return
					end
				else
					todo_text = todo_text .. " " .. args[i]
					i = i + 1
				end
			end

			todo_text = vim.trim(todo_text)
			if todo_text ~= "" then
				actions.create_todo(todo_text, priorities)
				local msg = "Todo created: " .. todo_text
				if priorities then
					msg = msg .. " (priorities: " .. table.concat(priorities, ", ") .. ")"
				end
				vim.notify(msg, vim.log.levels.INFO, { title = "Dooing" })
			end
		elseif command == "set" then
			if #args < 3 then
				vim.notify("Usage: Dooing set <index> <field> <value>", vim.log.levels.ERROR)
				return
			end

			local index = tonumber(args[1])
			local field = args[2]
			local value = args[3]

			if field == "ect" then
				actions.add_time_estimation(index, value)
			elseif field == "due" then
				actions.add_due_date(index, value)
			else
				vim.notify("Unknown field: " .. field, vim.log.levels.ERROR)
			end
		end
	end, {
		desc = "Toggle Todo List window or add new todo",
		nargs = "*",
		complete = function(arglead, cmdline, cursorpos)
			local args = vim.split(cmdline, "%s+", { trimempty = true })
			if #args <= 2 then
				return { "add", "list", "set" }
			elseif args[1] == "set" and #args == 3 then
				return { "priorities", "ect" }
			elseif args[1] == "set" and (args[3] == "priorities") then
				local priorities = { "nil" } -- Add nil as an option
				for _, p in ipairs(config.options.priorities) do
					table.insert(priorities, p.name)
				end
				return priorities
			elseif args[#args - 1] == "-p" or args[#args - 1] == "--priorities" then
				-- Return available priorities for completion
				local priorities = {}
				for _, p in ipairs(config.options.priorities) do
					table.insert(priorities, p.name)
				end
				return priorities
			elseif #args == 3 then
				return { "-p", "--priorities" }
			end
			return {}
		end,
	})

	-- Only set up keymap if it's enabled in config
	if config.options.keymaps.toggle_window then
		vim.keymap.set("n", config.options.keymaps.toggle_window, function()
			ui.toggle_todo_window()
		end, { desc = "Toggle Todo List" })
	end
end

return M

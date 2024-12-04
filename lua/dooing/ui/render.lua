local M = {}

-- Dependencies
local config = require("dooing.config")
local calendar = require("dooing.ui.windows.calendar")
local state = require("dooing.state")

-- Cache for highlight groups
local highlight_cache = {}

-- Namespace for highlighting
local ns_id = vim.api.nvim_create_namespace("dooing")

-- Setup highlight groups
local function setup_highlights()
	-- Clear highlight cache
	highlight_cache = {}

	-- Set up base highlights
	vim.api.nvim_set_hl(0, "DooingPending", { link = "Question", default = true })
	vim.api.nvim_set_hl(0, "DooingDone", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "DooingHelpText", { link = "Directory", default = true })

	-- Cache the base highlight groups
	highlight_cache.pending = "DooingPending"
	highlight_cache.done = "DooingDone"
	highlight_cache.help = "DooingHelpText"
end

-- Get highlight group for a set of priorities
local function get_priority_highlight(priorities)
	if not priorities or #priorities == 0 then
		return highlight_cache.pending
	end

	-- Sort priority groups by number of members (descending)
	local sorted_groups = {}
	for name, group in pairs(config.options.priority_groups) do
		table.insert(sorted_groups, { name = name, group = group })
	end
	table.sort(sorted_groups, function(a, b)
		return #a.group.members > #b.group.members
	end)

	-- Check priority groups from largest to smallest
	for _, group_data in ipairs(sorted_groups) do
		local group = group_data.group
		-- Check if all group members are present in the priorities
		local all_members_match = true
		for _, member in ipairs(group.members) do
			local found = false
			for _, priority in ipairs(priorities) do
				if priority == member then
					found = true
					break
				end
			end
			if not found then
				all_members_match = false
				break
			end
		end

		if all_members_match then
			-- Create cache key from group definition
			local cache_key = table.concat(group.members, "_")
			if highlight_cache[cache_key] then
				return highlight_cache[cache_key]
			end

			local hl_group = highlight_cache.pending
			if group.color and type(group.color) == "string" and group.color:match("^#%x%x%x%x%x%x$") then
				local hl_name = "Dooing" .. group.color:gsub("#", "")
				vim.api.nvim_set_hl(0, hl_name, { fg = group.color })
				hl_group = hl_name
			elseif group.hl_group then
				hl_group = group.hl_group
			end

			highlight_cache[cache_key] = hl_group
			return hl_group
		end
	end

	return highlight_cache.pending
end

-- Format a single todo item
function M.format_todo(todo, formatting, lang)
	if not formatting or not formatting.pending or not formatting.done then
		error("Invalid 'formatting' configuration in config.lua")
	end

	local components = {}

	-- Get config formatting
	local format = todo.done and formatting.done.format or formatting.pending.format
	if not format then
		format = { "icon", "text", "ect" } -- Default format
	end

	-- Breakdown config format and get dynamic text based on other configs
	for _, part in ipairs(format) do
		if part == "icon" then
			table.insert(components, todo.done and formatting.done.icon or formatting.pending.icon)
		elseif part == "text" then
			table.insert(components, todo.text)
		elseif part == "due_date" then
			-- Format due date if exists
			if todo.due_at then
				local date = os.date("*t", todo.due_at)
				local month = calendar.MONTH_NAMES[lang][date.month]
				local formatted_date
				if lang == "pt" or lang == "es" then
					formatted_date = string.format("%d de %s de %d", date.day, month, date.year)
				elseif lang == "fr" then
					formatted_date = string.format("%d %s %d", date.day, month, date.year)
				elseif lang == "de" or lang == "it" then
					formatted_date = string.format("%d %s %d", date.day, month, date.year)
				elseif lang == "jp" then
					formatted_date = string.format("%d年%s%d日", date.year, month, date.day)
				else
					formatted_date = string.format("%s %d, %d", month, date.day, date.year)
				end
				local due_date_str
				if config.options.calendar.icon ~= "" then
					due_date_str = "[" .. config.options.calendar.icon .. " " .. formatted_date .. "]"
				else
					due_date_str = "[" .. formatted_date .. "]"
				end
				local current_time = os.time()
				if not todo.done and todo.due_at < current_time then
					due_date_str = due_date_str .. " [OVERDUE]"
				end
				table.insert(components, due_date_str)
			end
		elseif part == "priority" then
			local score = state.get_priority_score(todo)
			table.insert(components, string.format("Priority: %d", score))
		elseif part == "ect" then
			if todo.estimated_hours then
				local time_str
				if todo.estimated_hours >= 168 then -- more than a week
					local weeks = todo.estimated_hours / 168
					time_str = string.format("[≈ %gw]", weeks)
				elseif todo.estimated_hours >= 24 then -- more than a day
					local days = todo.estimated_hours / 24
					time_str = string.format("[≈ %gd]", days)
				elseif todo.estimated_hours >= 1 then -- more than an hour
					time_str = string.format("[≈ %gh]", todo.estimated_hours)
				else -- less than an hour
					time_str = string.format("[≈ %gm]", todo.estimated_hours * 60)
				end
				table.insert(components, time_str)
			end
		end
	end

	return table.concat(components, " ")
end

-- Render todos to buffer
function M.render_todos(buf_id)
	if not buf_id then
		return
	end

	setup_highlights()

	-- Create the buffer
	vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
	vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)
	local lines = { "" }

	-- Sort todos and get config
	state.sort_todos()
	local lang = calendar and calendar.get_language()
	local formatting = config.options.formatting
	local done_icon = config.options.formatting.done.icon
	local pending_icon = config.options.formatting.pending.icon

	-- Loop through all todos and render them using the format
	for _, todo in ipairs(state.todos) do
		if not state.active_filter or todo.text:match("#" .. state.active_filter) then
			local todo_text = M.format_todo(todo, formatting, lang)
			table.insert(lines, "  " .. todo_text)
		end
	end

	if state.active_filter then
		table.insert(lines, 1, "")
		table.insert(lines, 1, "  Filtered by: #" .. state.active_filter)
	end

	table.insert(lines, "")

	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

	-- Helper function to add highlight
	local function add_hl(line_nr, start_col, end_col, hl_group)
		vim.api.nvim_buf_add_highlight(buf_id, ns_id, hl_group, line_nr, start_col, end_col)
	end

	-- Helper function to find pattern and highlight
	local function highlight_pattern(line, line_nr, pattern, hl_group)
		local start_idx = line:find(pattern)
		if start_idx then
			add_hl(line_nr, start_idx - 1, -1, hl_group)
		end
	end

	for i, line in ipairs(lines) do
		local line_nr = i - 1
		if line:match("^%s+[" .. done_icon .. pending_icon .. "]") then
			local todo_index = i - (state.active_filter and 3 or 1)
			local todo = state.todos[todo_index]

			if todo then
				-- Base todo highlight
				if todo.done then
					add_hl(line_nr, 0, -1, "DooingDone")
				else
					-- Get highlight based on priorities
					local hl_group = get_priority_highlight(todo.priorities)
					add_hl(line_nr, 0, -1, hl_group)
				end

				-- Tags highlight
				for tag in line:gmatch("#(%w+)") do
					local tag_pattern = "#" .. tag
					local start_idx = line:find(tag_pattern) - 1
					add_hl(line_nr, start_idx, start_idx + #tag_pattern, "Type")
				end

				-- Due date and overdue highlights
				highlight_pattern(line, line_nr, "%[@%d+/%d+/%d+%]", "Comment")
				highlight_pattern(line, line_nr, "%[OVERDUE%]", "ErrorMsg")
			end
		elseif line:match("Filtered by:") then
			add_hl(line_nr, 0, -1, "WarningMsg")
		end
	end

	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
end

return M

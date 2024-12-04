local M = {}

-- Dependencies
local config = require("dooing.config")
local state = require("dooing.state")

-- Local window IDs and buffers
local win_id = nil
local buf_id = nil

-- Namespace for highlighting
local ns_id = vim.api.nvim_create_namespace("dooing_tags")

-- Close tag window
local function close_window(main_win_id)
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_win_close(win_id, true)
		win_id = nil
		buf_id = nil
		if main_win_id and vim.api.nvim_win_is_valid(main_win_id) then
			vim.api.nvim_set_current_win(main_win_id)
		end
	end
end

-- Create and configure tag window
function M.create(main_win_id, render_callback)
	-- If window exists, close it and return
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		close_window(main_win_id)
		return
	end

	-- Create buffer
	buf_id = vim.api.nvim_create_buf(false, true)

	-- Configure window dimensions
	local width = 30
	local height = 10
	local ui = vim.api.nvim_list_uis()[1]
	local main_width = 40
	local main_col = math.floor((ui.width - main_width) / 2)
	local col = main_col - width - 2
	local row = math.floor((ui.height - height) / 2)

	-- Create window
	win_id = vim.api.nvim_open_win(buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " tags ",
		title_pos = "center",
	})

	-- Get and set tags content
	local tags = state.get_all_tags()
	if #tags == 0 then
		tags = { "No tags found" }
	end
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, tags)
	vim.api.nvim_buf_set_option(buf_id, "modifiable", true)

	-- Set up keymaps
	local keyopts = { buffer = buf_id, nowait = true }

	-- Select tag
	vim.keymap.set("n", "<CR>", function()
		local cursor = vim.api.nvim_win_get_cursor(win_id)
		local tag = vim.api.nvim_buf_get_lines(buf_id, cursor[1] - 1, cursor[1], false)[1]
		if tag ~= "No tags found" then
			state.set_filter(tag)
			close_window(main_win_id)
			if render_callback then
				render_callback()
			end
		end
	end, keyopts)

	-- Edit tag
	vim.keymap.set("n", config.options.keymaps.edit_tag, function()
		local cursor = vim.api.nvim_win_get_cursor(win_id)
		local old_tag = vim.api.nvim_buf_get_lines(buf_id, cursor[1] - 1, cursor[1], false)[1]
		if old_tag ~= "No tags found" then
			vim.ui.input({ prompt = "Edit tag: ", default = old_tag }, function(new_tag)
				if new_tag and new_tag ~= "" and new_tag ~= old_tag then
					state.rename_tag(old_tag, new_tag)
					local updated_tags = state.get_all_tags()
					vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, updated_tags)
					if render_callback then
						render_callback()
					end
				end
			end)
		end
	end, keyopts)

	-- Delete tag
	vim.keymap.set("n", config.options.keymaps.delete_tag, function()
		local cursor = vim.api.nvim_win_get_cursor(win_id)
		local tag = vim.api.nvim_buf_get_lines(buf_id, cursor[1] - 1, cursor[1], false)[1]
		if tag ~= "No tags found" then
			state.delete_tag(tag)
			local updated_tags = state.get_all_tags()
			if #updated_tags == 0 then
				updated_tags = { "No tags found" }
			end
			vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, updated_tags)
			if render_callback then
				render_callback()
			end
		end
	end, keyopts)

	-- Close window
	vim.keymap.set("n", config.options.keymaps.close_window, function()
		close_window(main_win_id)
	end, keyopts)
end

-- Get window and buffer IDs
function M.get_ids()
	return {
		win_id = win_id,
		buf_id = buf_id,
	}
end

-- Check if window is valid
function M.is_valid()
	return win_id and vim.api.nvim_win_is_valid(win_id)
end

-- Close window (public interface)
function M.close(main_win_id)
	close_window(main_win_id)
end

return M

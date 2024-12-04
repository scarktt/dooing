local M = {}

-- Dependencies
local config = require("dooing.config")

-- Local window IDs and buffers
local win_id = nil
local buf_id = nil

-- Namespace for highlighting
local ns_id = vim.api.nvim_create_namespace("dooing_help")

-- Content configuration
local HELP_CONTENT = {
	" Main window:",
	" i           - Add new to-do",
	" x           - Toggle to-do status",
	" d           - Delete current to-do",
	" D           - Delete all completed todos",
	" q           - Close window",
	" H           - Add due date to to-do ",
	" r           - Remove to-do due date",
	" T           - Add time estimation",
	" R           - Remove time estimation",
	" ?           - Toggle this help window",
	" t           - Toggle tags window",
	" c           - Clear active tag filter",
	" e           - Edit to-do item",
	" u           - Undo deletition",
	" /           - Search todos",
	" I           - Import todos",
	" E           - Export todos",
	" <leader>D   - Remove duplicates",
	" ",
	" Tags window:",
	" e     - Edit tag",
	" d     - Delete tag",
	" <CR>  - Filter by tag",
	" q     - Close window",
	" ",
}

-- Close help window
local function close_window()
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_win_close(win_id, true)
		win_id = nil
		buf_id = nil
	end
end

-- Create and configure help window
function M.create()
	-- If window exists, close it and return
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		close_window()
		return
	end

	-- Create buffer
	buf_id = vim.api.nvim_create_buf(false, true)

	-- Configure window dimensions
	local width = 50
	local height = 20
	local ui = vim.api.nvim_list_uis()[1]
	local col = math.floor((ui.width - width) / 2) + width + 2
	local row = math.floor((ui.height - height) / 2)

	-- Create window
	win_id = vim.api.nvim_open_win(buf_id, false, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " help ",
		title_pos = "center",
		zindex = 100,
	})

	-- Set buffer content
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, HELP_CONTENT)
	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
	vim.api.nvim_buf_set_option(buf_id, "buftype", "nofile")

	-- Apply highlights
	for i = 0, #HELP_CONTENT - 1 do
		vim.api.nvim_buf_add_highlight(buf_id, ns_id, "DooingHelpText", i, 0, -1)
	end

	-- Auto-close on buffer leave
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = buf_id,
		callback = function()
			close_window()
			return true
		end,
	})

	-- Set up keymaps
	local keyopts = { buffer = buf_id, nowait = true }
	vim.keymap.set("n", config.options.keymaps.close_window, close_window, keyopts)
	vim.keymap.set("n", config.options.keymaps.toggle_help, close_window, keyopts)

	return {
		win_id = win_id,
		buf_id = buf_id,
	}
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
function M.close()
	close_window()
end

return M

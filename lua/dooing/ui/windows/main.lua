local M = {}

-- Dependencies
local config = require("dooing.config")
local state = require("dooing.state")

-- Local window IDs and buffers
local win_id = nil
local buf_id = nil

-- Creates and configures the small keys window
local function create_small_keys_window(main_win_pos)
	if not config.options.quick_keys then
		return nil
	end

	local small_buf = vim.api.nvim_create_buf(false, true)
	local width = config.options.window.width

	-- Define two separate line arrays for each column
	local lines_1 = {
		"",
		"  i - New todo",
		"  x - Toggle todo",
		"  d - Delete todo",
		"  u - Undo delete",
		"  H - Add due date",
		"",
	}

	local lines_2 = {
		"",
		"  T - Add time",
		"  t - Tags",
		"  / - Search",
		"  I - Import",
		"  E - Export",
		"",
	}

	-- Calculate middle point for even spacing
	local mid_point = math.floor(width / 2)
	local padding = 2

	-- Create combined lines with centered columns
	local lines = {}
	for i = 1, #lines_1 do
		local line1 = lines_1[i] .. string.rep(" ", mid_point - #lines_1[i] - padding)
		local line2 = lines_2[i] or ""
		lines[i] = line1 .. line2
	end

	vim.api.nvim_buf_set_lines(small_buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(small_buf, "modifiable", false)
	vim.api.nvim_buf_set_option(small_buf, "buftype", "nofile")

	-- Position it under the main window
	local row = main_win_pos.row + main_win_pos.height + 1

	local small_win = vim.api.nvim_open_win(small_buf, false, {
		relative = "editor",
		row = row,
		col = main_win_pos.col,
		width = width,
		height = #lines,
		style = "minimal",
		border = "rounded",
		focusable = false,
		zindex = 45,
		footer = " Quick Keys ",
		footer_pos = "center",
	})

	-- Add highlights
	local ns = vim.api.nvim_create_namespace("dooing_small_keys")

	-- Highlight title
	vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickTitle", 0, 0, -1)

	-- Highlight each key and description in both columns
	for i = 1, #lines - 1 do
		if i > 0 then
			-- Left column
			vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickKey", i, 2, 3)
			vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickDesc", i, 5, mid_point - padding)

			-- Right column
			local right_key_start = mid_point
			vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickKey", i, right_key_start + 2, right_key_start + 3)
			vim.api.nvim_buf_add_highlight(small_buf, ns, "DooingQuickDesc", i, right_key_start + 5, -1)
		end
	end

	return small_win
end

-- Setup window keymaps
local function setup_window_keymaps(buf_id, callbacks)
	local function setup_keymap(key_option, callback)
		if config.options.keymaps[key_option] then
			vim.keymap.set("n", config.options.keymaps[key_option], callback, { buffer = buf_id, nowait = true })
		end
	end

	for key, callback in pairs(callbacks) do
		setup_keymap(key, callback)
	end
end

-- Create and configure main window
function M.create(callbacks)
	local ui = vim.api.nvim_list_uis()[1]
	local width = config.options.window.width
	local height = config.options.window.height
	local col = math.floor((ui.width - width) / 2)
	local row = math.floor((ui.height - height) / 2)

	-- Create buffer
	buf_id = vim.api.nvim_create_buf(false, true)

	-- Create window
	win_id = vim.api.nvim_open_win(buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " to-dos ",
		title_pos = "center",
		footer = " [?] for help ",
		footer_pos = "center",
	})

	-- Create small keys window with main window position
	local small_win = create_small_keys_window({
		row = row,
		col = col,
		width = width,
		height = height,
	})

	-- Close small window when main window is closed
	if small_win then
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(win_id),
			callback = function()
				if vim.api.nvim_win_is_valid(small_win) then
					vim.api.nvim_win_close(small_win, true)
				end
			end,
		})
	end

	-- Set window options
	vim.api.nvim_win_set_option(win_id, "wrap", true)
	vim.api.nvim_win_set_option(win_id, "linebreak", true)
	vim.api.nvim_win_set_option(win_id, "breakindent", true)
	vim.api.nvim_win_set_option(win_id, "breakindentopt", "shift:2")
	vim.api.nvim_win_set_option(win_id, "showbreak", " ")

	-- Setup keymaps
	setup_window_keymaps(buf_id, callbacks)

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

-- Close window
function M.close()
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_win_close(win_id, true)
		win_id = nil
		buf_id = nil
	end
end

return M

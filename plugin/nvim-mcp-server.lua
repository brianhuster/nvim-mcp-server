NvimMcpServer = {}

---@param buf string|number
---@return table
function NvimMcpServer.get_diagnostics_from_file(buf)
	local bufnr = type(buf) == "number" and buf or vim.fn.bufnr(buf)
	if bufnr < 0 then
		return {
			error = "File is not loaded by Nvim yet"
		}
	end
	local diagnostics = vim.diagnostic.get(bufnr)
	return vim.iter(diagnostics):map(function(diagnostic)
		return {
			line = diagnostic.lnum + 1,
			end_line = diagnostic.end_lnum + 1,
			col = diagnostic.col,
			end_col = diagnostic.end_col,
			text = table.concat(vim.api.nvim_buf_get_lines(bufnr, diagnostic.lnum, diagnostic.end_lnum + 1, false), '\n'),
			message = diagnostic.message,
			severity = diagnostic.severity,
			source = diagnostic.source,
		}
	end):totable()
end

---@param win number
---@param lines number?
---@return string
function NvimMcpServer.get_win_text(win, lines)
	local wininfo = vim.fn.getwininfo(win)[1]
	local start_line = wininfo.topline - 1
	local end_line = wininfo.botline
	if lines and lines > 0 then
		end_line = start_line + lines
	end
	return vim.iter(vim.api.nvim_buf_get_lines(wininfo.bufnr, start_line, end_line, false))
		:join('\n')
end

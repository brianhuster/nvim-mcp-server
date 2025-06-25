NvimMcpServer = {}

---@param buf string|number
---@return table
function NvimMcpServer.get_diagnostics_from_file(buf)
	local bufnr = type(buf) == "number" and buf or vim.fn.bufnr(buf, true)
	if bufnr < 0 then
		return {
			error = "File is not loaded by Nvim yet"
		}
	end
	local diagnostics = vim.diagnostic.get(bufnr)
	local severity_map = {
		[vim.diagnostic.severity.ERROR] = "Error",
		[vim.diagnostic.severity.WARN] = "Warning",
		[vim.diagnostic.severity.INFO] = "Information",
		[vim.diagnostic.severity.HINT] = "Hint",
	}
	return vim.iter(diagnostics):map(
		---@param diagnostic vim.Diagnostic
		function(diagnostic)
			local line_number = diagnostic.lnum + 1
			return {
				line_number = line_number,
				line_content = vim.fn.getline(line_number),
				message = diagnostic.message,
				severity = severity_map[diagnostic.severity],
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

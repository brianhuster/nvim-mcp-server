if vim.g.NvimMcpServerLoaded then
	return
end
vim.g.NvimMcpServerLoaded = true

local M = {}
local api, iter = vim.api, vim.iter

---@class ParsedSymbol
---@field name string
---@field name_path string
---@field kind integer
---@field detail string|nil
---@field location {uri: string, range: any}|nil
---@field range {start: {line: integer, character: integer}, ["end"]: {line: integer, character: integer}}|nil
---@field children ParsedSymbol[]|nil
---@field relative_path string|nil
---@field content_around_reference string|nil

---@param symbols any[]
---@param result ParsedSymbol[]
---@param prefix string
---@return ParsedSymbol[]
local function parse_symbol_tree(symbols, result, prefix)
	prefix = prefix or ""
	result = result or {}
	if not symbols or #symbols == 0 then
		return result
	end
	for _, symbol in ipairs(symbols) do
		if symbol.name then
			local name_path = prefix .. symbol.name

			---@type {uri: string, range: any}|nil
			local location = symbol.location
			if not location then
				location = { uri = symbol.uri, range = symbol.range }
			end

			---@type {start: {line: integer, character: integer}, ["end"]: {line: integer, character: integer}}|nil
			local range = symbol.range
			if not range and location then
				range = location.range
			end

			---@type ParsedSymbol
			local parsed = {
				name = symbol.name,
				name_path = name_path,
				kind = symbol.kind,
				detail = symbol.detail,
				location = location,
				range = range,
				children = nil,
				relative_path = nil,
				content_around_reference = nil
			}
			table.insert(result, parsed)

			if symbol.children and #symbol.children > 0 then
				parsed.children = symbol.children
				parse_symbol_tree(symbol.children, result, name_path .. "/")
			end
		end
	end
	return result
end

---@param symbols ParsedSymbol[]
---@param name_path string
---@return ParsedSymbol|nil
local function find_symbol_by_name_path(symbols, name_path)
	---@type string[]
	local parts = {}
	for part in string.gmatch(name_path, "([^/]+)") do
		table.insert(parts, part)
	end

	---@param syms ParsedSymbol[]|nil
	---@param depth integer
	---@return ParsedSymbol|nil
	local function find_in_symbols(syms, depth)
		if depth > #parts then
			return nil
		end
		local target_name = parts[depth]
		for _, sym in ipairs(syms or {}) do
			if sym.name == target_name then
				if depth == #parts then
					return sym
				elseif sym.children then
					local found = find_in_symbols(---@cast syms ParsedSymbol[], sym.children, depth + 1)
					if found then return found end
				end
			end
		end
		return nil
	end

	return find_in_symbols(symbols, 1)
end

---@type table<vim.diagnostic.Severity, string>
local severity_map = {}
for k, v in pairs(vim.diagnostic.severity) do
	severity_map[v] = k
end

---@param path string
---@param lnum integer
---@param col integer
---@param end_lnum integer
---@param end_col integer
---@return string
local function get_path_with_line_col(path, lnum, col, end_lnum, end_col)
	if end_lnum > lnum then
		return ("%s:%d.%d-%d:%d"):format(path, lnum + 1, col + 1, end_lnum + 1, end_col)
	elseif end_col > col then
		return ("%s:%d.%d-%d"):format(path, lnum + 1, col + 1, end_col)
	else
		return ("%s:%d.%d"):format(path, lnum + 1, col + 1)
	end
end

---@param bufname string
---@return string
function M.get_diagnostics(bufname)
	local buf
	if bufname ~= "" then
		buf = vim.fn.bufnr(bufname)
		if buf < 0 and vim.fn.filereadable(bufname) == 0 then
			return "File not found: " .. bufname
		end
	end
	---@type vim.Diagnostic[]
	local diagnostics = vim.diagnostic.get(buf)
	return iter(diagnostics):map(
		---@param d vim.Diagnostic
		function(d)
			local lnum = d.lnum
			local d_bufname = vim.api.nvim_buf_get_name(d.bufnr)
			local path = vim.fs.relpath(vim.fn.getcwd(), d_bufname) or d_bufname
			local path_with_lnum_col = get_path_with_line_col(path, lnum, d.col, d.end_lnum, d.end_col)
			return ("%s [%s] %s\n%s"):format(
				path_with_lnum_col,
				severity_map[d.severity],
				d.message,
				iter(api.nvim_buf_get_lines(d.bufnr, lnum, d.end_lnum + 1, false)):join("\n")
			)
		end):join("\n")
end

---@param bufnr integer
---@return any[]
local function get_document_symbols(bufnr)
	---@type {id: integer, name: string, server_capabilities: any, attached_buffers: table<integer, boolean>}[]
	local clients = vim.lsp.get_clients({ bufnr = bufnr })
	if #clients == 0 then
		return {}
	end

	---@type {textDocument: {uri: string}}
	local params = {
		textDocument = {
			uri = vim.uri_from_bufnr(bufnr)
		}
	}
	local result = vim.lsp.buf_request_sync(bufnr, "textDocument/documentSymbol", params, 1000)
	---@type any[]
	local symbols = {}
	for _, response in pairs(result or {}) do
		if response and response.result then
			for _, sym in ipairs(response.result) do
				table.insert(symbols, sym)
			end
		end
	end
	return symbols
end

--- Group symbols by kind
---@param symbols ParsedSymbol[]
---@return table<string, ParsedSymbol[]>
local function group_by_kind(symbols)
	---@type table<string, ParsedSymbol[]>
	local groups = {}
	for _, sym in ipairs(symbols) do
		local kind_name = vim.lsp.protocol.SymbolKind[sym.kind] or "Unknown"
		if not groups[kind_name] then
			groups[kind_name] = {}
		end
		table.insert(groups[kind_name], sym)
	end
	return groups
end

---Get content around a line in a buffer
---@param bufnr integer
---@param line integer
---@param context_before integer
---@param context_after integer
---@return string
local function get_content_around_line(bufnr, line, context_before, context_after)
	local lines = api.nvim_buf_get_lines(bufnr, line - context_before, line + context_after + 1, false)
	return table.concat(lines, "\n")
end

---@param relative_path string
---@param depth integer|nil
---@return table
function M.get_symbols_overview(relative_path, depth)
	depth = depth or 0
	local abs_path = vim.fn.fnamemodify(relative_path, ":p")
	if vim.fn.filereadable(abs_path) == 0 then
		return { error = "File not found: " .. relative_path }
	end

	local bufnr = vim.fn.bufadd(abs_path)
	vim.fn.bufload(bufnr)
	local symbols = get_document_symbols(bufnr)
	if not symbols or #symbols == 0 then
		return {}
	end

	local parsed = parse_symbol_tree(symbols, {}, "")
	-- Add relative_path to each symbol
	for _, sym in ipairs(parsed) do
		sym.relative_path = relative_path
	end

	-- Group by kind like Serena
	local grouped = group_by_kind(parsed)
	return grouped
end

---@param name_path_pattern string
---@param relative_path string|nil
---@param depth integer|nil
---@return ParsedSymbol[]
function M.find_symbol(name_path_pattern, relative_path, depth)
	depth = depth or 0
	local bufnr = nil

	if relative_path and relative_path ~= "" then
		local abs_path = vim.fn.fnamemodify(relative_path, ":p")
		if vim.fn.filereadable(abs_path) == 1 then
			bufnr = vim.fn.bufadd(abs_path)
			vim.fn.bufload(bufnr)
		end
	end

	if not bufnr then
		bufnr = api.nvim_get_current_buf()
	end

	local symbols = get_document_symbols(bufnr)
	if symbols and #symbols > 0 then
		local parsed = parse_symbol_tree(symbols, {}, "")

		local pattern = name_path_pattern:lower()
		---@type ParsedSymbol[]
		local results = {}

		---@param sym ParsedSymbol
		---@return boolean
		local function match_symbol(sym)
			local name_lower = sym.name:lower()
			return name_lower:find(pattern, 1, true) ~= nil
		end

		---@param syms ParsedSymbol[]|nil
		local function collect_matches(syms)
			for _, sym in ipairs(syms or {}) do
				if match_symbol(sym) then
					sym.relative_path = relative_path
					table.insert(results, sym)
				end
				if sym.children and depth > 0 then
					collect_matches(sym.children)
				end
			end
		end

		collect_matches(parsed)

		return results
	end
	return {}
end

---@param name_path string
---@param relative_path string
---@return table
function M.find_referencing_symbols(name_path, relative_path)
	local abs_path = vim.fn.fnamemodify(relative_path, ":p")
	if vim.fn.filereadable(abs_path) == 0 then
		return { error = "File not found: " .. relative_path }
	end

	local bufnr = vim.fn.bufadd(abs_path)
	vim.fn.bufload(bufnr)

	local symbols = get_document_symbols(bufnr)
	if not symbols or #symbols == 0 then
		return { error = "No symbols found in file" }
	end

	local parsed = parse_symbol_tree(symbols, {}, "")
	local target_sym = find_symbol_by_name_path(parsed, name_path)

	if not target_sym then
		return { error = "Symbol not found: " .. name_path }
	end

	local range = target_sym.range or target_sym.location.range

	local params = {
		textDocument = {
			uri = vim.uri_from_bufnr(bufnr)
		},
		position = {
			line = range.start.line,
			character = range.start.character
		},
		context = {
			includeDeclaration = false
		}
	}

	local results = vim.lsp.buf_request_sync(bufnr, "textDocument/references", params, 1000)

	---@type ParsedSymbol[]
	local refs = {}
	for _, resp in pairs(results or {}) do
		if resp and resp.result then
			for _, ref in ipairs(resp.result) do
				local ref_uri = ref.uri or ref.location.uri
				local ref_range = ref.range or ref.location.range
				-- Convert uri to relative path
				local ref_bufnr = vim.uri_to_bufnr(ref_uri)
				local ref_abs_path = api.nvim_buf_get_name(ref_bufnr)
				local ref_rel_path = vim.fs.relpath(vim.fn.getcwd(), ref_abs_path) or ref_abs_path

				-- Get content around reference
				local ref_line = ref_range.start.line
				local content = get_content_around_line(ref_bufnr, ref_line, 1, 1)

				---@type ParsedSymbol
				local ref_sym = {
					name = "",
					name_path = "",
					kind = 0,
					detail = nil,
					location = { uri = ref_uri, range = ref_range },
					range = ref_range,
					children = nil,
					relative_path = ref_rel_path,
					content_around_reference = content
				}

				-- Try to get symbol info at that location
				local ref_syms = get_document_symbols(ref_bufnr)
				if ref_syms and #ref_syms > 0 then
					local ref_parsed = parse_symbol_tree(ref_syms, {}, "")
					-- Find symbol at the reference position
					for _, s in ipairs(ref_parsed) do
						if s.range and s.range.start.line == ref_line then
							ref_sym.name = s.name
							ref_sym.name_path = s.name_path
							ref_sym.kind = s.kind
							ref_sym.detail = s.detail
							break
						end
					end
				end

				table.insert(refs, ref_sym)
			end
		end
	end

	-- Group by relative_path and kind like Serena
	---@type table<string, table<string, ParsedSymbol[]>>
	local grouped = {}
	for _, ref in ipairs(refs) do
		local rel_path = ref.relative_path or "unknown"
		local kind_name = vim.lsp.protocol.SymbolKind[ref.kind] or "Unknown"
		if not grouped[rel_path] then
			grouped[rel_path] = {}
		end
		if not grouped[rel_path][kind_name] then
			grouped[rel_path][kind_name] = {}
		end
		table.insert(grouped[rel_path][kind_name], ref)
	end

	return grouped
end

---@param name_path string
---@param relative_path string
---@param body string
---@return table
function M.replace_symbol_body(name_path, relative_path, body)
	local abs_path = vim.fn.fnamemodify(relative_path, ":p")
	if vim.fn.filereadable(abs_path) == 0 then
		return { error = "File not found: " .. relative_path }
	end

	local bufnr = vim.fn.bufadd(abs_path)
	vim.fn.bufload(bufnr)

	local symbols = get_document_symbols(bufnr)
	if not symbols or #symbols == 0 then
		return { error = "No symbols found in file" }
	end

	local parsed = parse_symbol_tree(symbols, {}, "")
	local target_sym = find_symbol_by_name_path(parsed, name_path)

	if not target_sym then
		return { error = "Symbol not found: " .. name_path }
	end

	local range = target_sym.range or target_sym.location.range

	---@type any
	local text_edit = {
		range = range,
		newText = body
	}

	vim.lsp.util.apply_text_edits({ text_edit }, bufnr, "utf-8")

	return { success = true, message = "Symbol body replaced" }
end

---@param name_path string
---@param relative_path string
---@param body string
---@return table
function M.insert_after_symbol(name_path, relative_path, body)
	local abs_path = vim.fn.fnamemodify(relative_path, ":p")
	if vim.fn.filereadable(abs_path) == 0 then
		return { error = "File not found: " .. relative_path }
	end

	local bufnr = vim.fn.bufadd(abs_path)
	vim.fn.bufload(bufnr)

	local symbols = get_document_symbols(bufnr)
	if not symbols or #symbols == 0 then
		return { error = "No symbols found in file" }
	end

	local parsed = parse_symbol_tree(symbols, {}, "")
	local target_sym = find_symbol_by_name_path(parsed, name_path)

	if not target_sym then
		return { error = "Symbol not found: " .. name_path }
	end

	local range = target_sym.range or target_sym.location.range

	local insert_line = range["end"].line
	local insert_char = range["end"].character

	local new_text = "\n" .. body .. "\n"

	---@type any
	local text_edit = {
		range = {
			start = { line = insert_line, character = insert_char },
			["end"] = { line = insert_line, character = insert_char }
		},
		newText = new_text
	}

	vim.lsp.util.apply_text_edits({ text_edit }, bufnr, "utf-8")

	return { success = true, message = "Content inserted after symbol" }
end

---@param name_path string
---@param relative_path string
---@param body string
---@return table
function M.insert_before_symbol(name_path, relative_path, body)
	local abs_path = vim.fn.fnamemodify(relative_path, ":p")
	if vim.fn.filereadable(abs_path) == 0 then
		return { error = "File not found: " .. relative_path }
	end

	local bufnr = vim.fn.bufadd(abs_path)
	vim.fn.bufload(bufnr)

	local symbols = get_document_symbols(bufnr)
	if not symbols or #symbols == 0 then
		return { error = "No symbols found in file" }
	end

	local parsed = parse_symbol_tree(symbols, {}, "")
	local target_sym = find_symbol_by_name_path(parsed, name_path)

	if not target_sym then
		return { error = "Symbol not found: " .. name_path }
	end

	local range = target_sym.range or target_sym.location.range

	local insert_line = range.start.line
	local insert_char = 0

	local new_text = body .. "\n"

	---@type any
	local text_edit = {
		range = {
			start = { line = insert_line, character = insert_char },
			["end"] = { line = insert_line, character = insert_char }
		},
		newText = new_text
	}

	vim.lsp.util.apply_text_edits({ text_edit }, bufnr, "utf-8")

	return { success = true, message = "Content inserted before symbol" }
end

---@param name_path string
---@param relative_path string
---@param new_name string
---@return table
function M.rename_symbol(name_path, relative_path, new_name)
	local abs_path = vim.fn.fnamemodify(relative_path, ":p")
	if vim.fn.filereadable(abs_path) == 0 then
		return { error = "File not found: " .. relative_path }
	end

	local bufnr = vim.fn.bufadd(abs_path)
	vim.fn.bufload(bufnr)

	local symbols = get_document_symbols(bufnr)
	if not symbols or #symbols == 0 then
		return { error = "No symbols found in file" }
	end

	local parsed = parse_symbol_tree(symbols, {}, "")
	local target_sym = find_symbol_by_name_path(parsed, name_path)

	if not target_sym then
		return { error = "Symbol not found: " .. name_path }
	end

	local range = target_sym.range or target_sym.location.range

	local params = {
		textDocument = {
			uri = vim.uri_from_bufnr(bufnr)
		},
		position = {
			line = range.start.line,
			character = range.start.character
		},
		newName = new_name
	}

	local result = vim.lsp.buf_request_sync(bufnr, "textDocument/rename", params, 2000)

	local success = false
	local changes_count = 0

	for _, resp in pairs(result or {}) do
		if resp and resp.result then
			if resp.result.changes then
				vim.lsp.util.apply_workspace_edit(resp.result, "utf-8")
				for _, _ in pairs(resp.result.changes) do
					changes_count = changes_count + 1
				end
				success = true
			elseif resp.result.documentChanges then
				vim.lsp.util.apply_workspace_edit(resp.result, "utf-8")
				changes_count = #resp.result.documentChanges
				success = true
			end
		end
	end

	if success then
		return { success = true, message = string.format("Renamed %s to %s (%d changes applied)", name_path, new_name, changes_count) }
	else
		return { error = "Rename failed - language server may not support rename" }
	end
end

---@return table
function M.restart_language_server()
	local clients = vim.lsp.get_clients()
	local count = 0
	for _, client in ipairs(clients) do
		client:stop()
		count = count + 1
	end

	vim.defer_fn(function()
		vim.cmd("LspRestart")
	end, 100)

	return { success = true, message = string.format("LSP servers restarted (%d clients)", count), restarted = count }
end

---@return table
function M.get_lsp_client_info()
	---@type {id: integer, name: string, server_capabilities: any, attached_buffers: table<integer, boolean>}[]
	local clients = vim.lsp.get_clients()
	return { clients = clients, count = #clients }
end

NvimMcpServer = M

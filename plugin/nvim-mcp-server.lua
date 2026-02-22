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

---@param symbols any[]
---@param result ParsedSymbol[]
---@param prefix string
---@return ParsedSymbol[]
local function parse_symbol_tree(symbols, result, prefix)
    prefix = prefix or ""
    result = result or {}
    for _, symbol in ipairs(symbols or {}) do
        local name_path = prefix .. symbol.name
        
        -- Handle both DocumentSymbol (hierarchical) and SymbolInformation (flat)
        -- DocumentSymbol: has range, children
        -- SymbolInformation: has location (with uri and range)
        local location = symbol.location or { uri = symbol.uri, range = symbol.range }
        local range = symbol.range or (location and location.range)
        
        table.insert(result, {
            name = symbol.name,
            name_path = name_path,
            kind = symbol.kind,
            detail = symbol.detail,
            location = location,
            range = range,
            children = symbol.children
        })
        if symbol.children then
            parse_symbol_tree(symbol.children, result, name_path .. "/")
        end
    end
    return result
end

local function get_lsp_clients()
    local clients = vim.lsp.get_clients()
    local result = {}
    for _, client in ipairs(clients) do
        table.insert(result, {
            id = client.id,
            name = client.name,
            server_capabilities = client.server_capabilities,
            attached_buffers = client.attached_buffers
        })
    end
    return result
end

local function find_symbol_by_name_path(symbols, name_path)
    local parts = {}
    for part in string.gmatch(name_path, "([^/]+)") do
        table.insert(parts, part)
    end

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
                    local found = find_in_symbols(sym.children, depth + 1)
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
    local diagnostics = vim.diagnostic.get(buf)
    return iter(diagnostics):map(
		---@param d vim.Diagnostic
        function(d)
            local lnum = d.lnum
			local d_bufname = vim.api.nvim_buf_get_name(d.bufnr)
            local path = vim.fs.relpath(vim.fn.getcwd(), d_bufname) or d_bufname
            local path_with_lnum_col = get_path_with_line_col(path, lnum, d.col, d.end_lnum, d.end_col)
			return ("%s [%s] %s\n````%s\n%s````"):format(
				path_with_lnum_col,
				severity_map[d.severity],
                d.message,
				vim.bo[d.bufnr].filetype,
				iter(api.nvim_buf_get_lines(d.bufnr, lnum, d.end_lnum + 1, false)):join("\n")
			)
        end):join("\n\n")
end

local function get_document_symbols()
    local params = vim.lsp.util.make_text_document_params()
    local result = vim.lsp.buf_request_sync(0, "textDocument/documentSymbol", params, 1000)
    local symbols = {}
    for _, response in pairs(result or {}) do
        if response.result then
            for _, sym in ipairs(response.result) do
                table.insert(symbols, sym)
            end
        end
    end
    return symbols
end

function M.get_symbols_overview(relative_path, depth)
    depth = depth or 0
    local abs_path = vim.fn.fnamemodify(relative_path, ":p")
    if vim.fn.filereadable(abs_path) == 0 then
        return {error = "File not found: " .. relative_path}
    end

    vim.cmd("edit " .. abs_path)
    local symbols = get_document_symbols()
    if symbols and #symbols > 0 then
        local parsed = parse_symbol_tree(symbols, {}, "")
        return {symbols = parsed}
    end
    return {message = "No symbols found in file", symbols = {}}
end

function M.find_symbol(name_path_pattern, relative_path, depth)
    depth = depth or 0

    if relative_path and relative_path ~= "" then
        local abs_path = vim.fn.fnamemodify(relative_path, ":p")
        if vim.fn.filereadable(abs_path) == 1 then
            vim.cmd("edit " .. abs_path)
        end
    end

    local symbols = get_document_symbols()
    if symbols and #symbols > 0 then
        local parsed = parse_symbol_tree(symbols, {}, "")

        local pattern = name_path_pattern:lower()
        local results = {}

        local function match_symbol(sym)
            local name_lower = sym.name:lower()
            return name_lower:find(pattern, 1, true) ~= nil
        end

        local function collect_matches(syms)
            for _, sym in ipairs(syms or {}) do
                if match_symbol(sym) then
                    table.insert(results, sym)
                end
                if sym.children and depth > 0 then
                    collect_matches(sym.children)
                end
            end
        end

        collect_matches(parsed)

        if #results > 0 then
            return {symbols = results}
        end
    end
    return {message = "No symbols found matching: " .. name_path_pattern, symbols = {}}
end

function M.find_referencing_symbols(name_path, relative_path)
    local abs_path = vim.fn.fnamemodify(relative_path, ":p")
    if vim.fn.filereadable(abs_path) == 0 then
        return {error = "File not found: " .. relative_path}
    end

    vim.cmd("edit " .. abs_path)

    local symbols = get_document_symbols()
    if not symbols or #symbols == 0 then
        return {error = "No symbols found in file"}
    end

    local parsed = parse_symbol_tree(symbols, {}, "")
    local target_sym = find_symbol_by_name_path(parsed, name_path)

    if not target_sym then
        return {error = "Symbol not found: " .. name_path}
    end

    local range = target_sym.range or target_sym.location.range
    local params = {
        textDocument = vim.lsp.util.make_text_document_params(),
        position = {
            line = range.start.line,
            character = range.start.character
        }
    }

    local results = vim.lsp.buf.request_sync("textDocument/references", params, 1000)

    local refs = {}
    for client_id, resp in pairs(results or {}) do
        if resp.result then
            for _, ref in ipairs(resp.result) do
                table.insert(refs, {
                    uri = ref.uri,
                    range = ref.range
                })
            end
        end
    end

    if #refs == 0 then
        return {message = "No references found", references = {}}
    end
    return {references = refs, symbol_name = name_path}
end

function M.replace_symbol_body(name_path, relative_path, body)
    local abs_path = vim.fn.fnamemodify(relative_path, ":p")
    if vim.fn.filereadable(abs_path) == 0 then
        return {error = "File not found: " .. relative_path}
    end

    vim.cmd("edit " .. abs_path)

    local symbols = get_document_symbols()
    if not symbols or #symbols == 0 then
        return {error = "No symbols found in file"}
    end

    local parsed = parse_symbol_tree(symbols, {}, "")
    local target_sym = find_symbol_by_name_path(parsed, name_path)

    if not target_sym then
        return {error = "Symbol not found: " .. name_path}
    end

    local range = target_sym.range or target_sym.location.range
    local new_text = body

    local text_edit = {
        range = range,
        newText = new_text
    }

    vim.lsp.util.apply_text_edits({text_edit}, 0, "utf-8")

    return {success = true, message = "Symbol body replaced"}
end

function M.insert_after_symbol(name_path, relative_path, body)
    local abs_path = vim.fn.fnamemodify(relative_path, ":p")
    if vim.fn.filereadable(abs_path) == 0 then
        return {error = "File not found: " .. relative_path}
    end

    vim.cmd("edit " .. abs_path)

    local symbols = get_document_symbols()
    if not symbols or #symbols == 0 then
        return {error = "No symbols found in file"}
    end

    local parsed = parse_symbol_tree(symbols, {}, "")
    local target_sym = find_symbol_by_name_path(parsed, name_path)

    if not target_sym then
        return {error = "Symbol not found: " .. name_path}
    end

    local range = target_sym.range or target_sym.location.range
    local insert_line = range["end"].line
    local insert_char = range["end"].character

    local new_text = "\n" .. body .. "\n"

    local text_edit = {
        range = {
            start = {line = insert_line, character = insert_char},
            ["end"] = {line = insert_line, character = insert_char}
        },
        newText = new_text
    }

    vim.lsp.util.apply_text_edits({text_edit}, 0, "utf-8")

    return {success = true, message = "Content inserted after symbol"}
end

function M.insert_before_symbol(name_path, relative_path, body)
    local abs_path = vim.fn.fnamemodify(relative_path, ":p")
    if vim.fn.filereadable(abs_path) == 0 then
        return {error = "File not found: " .. relative_path}
    end

    vim.cmd("edit " .. abs_path)

    local symbols = get_document_symbols()
    if not symbols or #symbols == 0 then
        return {error = "No symbols found in file"}
    end

    local parsed = parse_symbol_tree(symbols, {}, "")
    local target_sym = find_symbol_by_name_path(parsed, name_path)

    if not target_sym then
        return {error = "Symbol not found: " .. name_path}
    end

    local range = target_sym.range or target_sym.location.range
    local insert_line = range.start.line
    local insert_char = 0

    local new_text = body .. "\n"

    local text_edit = {
        range = {
            start = {line = insert_line, character = insert_char},
            ["end"] = {line = insert_line, character = insert_char}
        },
        newText = new_text
    }

    vim.lsp.util.apply_text_edits({text_edit}, 0, "utf-8")

    return {success = true, message = "Content inserted before symbol"}
end

function M.rename_symbol(name_path, relative_path, new_name)
    local abs_path = vim.fn.fnamemodify(relative_path, ":p")
    if vim.fn.filereadable(abs_path) == 0 then
        return {error = "File not found: " .. relative_path}
    end

    vim.cmd("edit " .. abs_path)

    local symbols = get_document_symbols()
    if not symbols or #symbols == 0 then
        return {error = "No symbols found in file"}
    end

    local parsed = parse_symbol_tree(symbols, {}, "")
    local target_sym = find_symbol_by_name_path(parsed, name_path)

    if not target_sym then
        return {error = "Symbol not found: " .. name_path}
    end

    local range = target_sym.range or target_sym.location.range
    local params = {
        textDocument = vim.lsp.util.make_text_document_params(),
        position = {
            line = range.start.line,
            character = range.start.character
        },
        newName = new_name
    }

    local result = vim.lsp.buf.request_sync("textDocument/rename", params, 2000)

    local success = false
    local changes_count = 0

    for client_id, resp in pairs(result or {}) do
        if resp.result then
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
        return {success = true, message = string.format("Renamed %s to %s (%d changes applied)", name_path, new_name, changes_count)}
    else
        return {error = "Rename failed - language server may not support rename"}
    end
end

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

    return {success = true, message = string.format("LSP servers restarted (%d clients)", count), restarted = count}
end

function M.get_lsp_client_info()
    local clients = get_lsp_clients()
    return {clients = clients, count = #clients}
end

NvimMcpServer = M

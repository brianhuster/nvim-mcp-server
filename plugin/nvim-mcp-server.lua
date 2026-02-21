local M = {}

---@param buf string|number
---@return string
function M.get_diagnostics_from_file(buf)
    local bufnr = type(buf) == "number" and buf or vim.fn.bufnr(buf, true)
    if bufnr < 0 then
        return "File is not loaded by Nvim yet"
    end
    local diagnostics = vim.diagnostic.get(bufnr)
    local severity_map = {
        [vim.diagnostic.severity.ERROR] = "Error",
        [vim.diagnostic.severity.WARN] = "Warning",
        [vim.diagnostic.severity.INFO] = "Information",
        [vim.diagnostic.severity.HINT] = "Hint",
    }
    return vim.inspect(vim.iter(diagnostics):map(
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
        end):totable())
end

NvimMcpServer = M

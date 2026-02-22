import os
import sys
from os.path import dirname

from fastmcp import FastMCP
from pynvim import attach

NVIM = os.environ.get("NVIM")
if not NVIM:
    raise RuntimeError("$NVIM environment variable is not set")
vim = attach("socket", path=NVIM)

mcp = FastMCP(
    name="nvim-mcp-server",
    instructions="This is an MCP that allows you to control a Nvim instance",
)


PLUGIN_PATH = os.path.join(
    dirname(dirname(dirname(os.path.abspath(__file__)))),
    "plugin",
    "nvim-mcp-server.lua",
)

vim.command(f"luafile {PLUGIN_PATH}")


@mcp.tool()
def execute_vimscript(code: str) -> str:
    """
    Execute Vimscript code and return the output.

    :param command: Vimscript code to execute
    """
    try:
        result = vim.api.exec2(code, {"output": True})
        return str(result) if result else ""
    except Exception as e:
        return f"Error: {type(e).__name__}: {e}"


@mcp.tool()
def execute_lua(code: str) -> str:
    """
    Executes Lua code. Arguments are available as `...` inside the chunk. The
    chunk can return a value.

    Only statements are executed. To evaluate an expression, prefix it with
    "return": `return my_function(...)`

    :param code: The Lua code to execute (use 'return' to return a value)
    """
    try:
        result = vim.exec_lua(code)
        if result is None:
            return "nil"
        return str(result)
    except Exception as e:
        return f"Error: {type(e).__name__}: {e}"


@mcp.tool()
def get_diagnostics(relative_path: str = "") -> str:
    """
    Get diagnostics for a given file or all opening files in Nvim.

    Use this tool to get information about errors, warnings, and other diagnostics reported by the language server.
    This should be called after performing edits to check for any new issues or to verify that existing issues have been resolved.

    :param relative_path: Optional. The relative path to the file to get diagnostics for. If not provided, diagnostics for all open files will be returned.
    """
    try:
        return vim.lua.NvimMcpServer.get_diagnostics(relative_path)
    except Exception as e:
        return f"Error: {type(e).__name__}: {e}"


@mcp.tool()
def get_symbols_overview(relative_path: str, depth: int = 0) -> list | str:
    """
    Gets an overview of the top-level symbols defined in a given file.

    Use this tool to get a high-level understanding of the code symbols in a file.
    This should be the first tool to call when you want to understand a new file.

    :param relative_path: the relative path to the file to get the overview of
    :param depth: depth up to which descendants of top-level symbols shall be retrieved
        (e.g. 1 retrieves immediate children). Default 0.
    :return: a dict containing symbols.
    """
    return vim.lua.NvimMcpServer.get_symbols_overview(relative_path, depth)


@mcp.tool()
def find_symbol(
    name_path_pattern: str, relative_path: str = "", depth: int = 0
) -> dict:
    """
    Performs a global (or local) search for symbols using the language server.

    :param name_path_pattern: the name path matching pattern (e.g. "MyClass/my_method")
    :param relative_path: Optional. Restrict search to this file or directory.
    :param depth: depth up to which descendants shall be retrieved. Default 0.
    :return: a dict with symbols matching the name.
    """
    return vim.lua.NvimMcpServer.find_symbol(name_path_pattern, relative_path, depth)


@mcp.tool()
def find_referencing_symbols(name_path: str, relative_path: str) -> list:
    """
    Finds symbols that reference the given symbol.

    :param name_path: the name path of the symbol to find references for (e.g. "MyClass/my_method")
    :param relative_path: the relative path to the file containing the symbol
    :return: a dict with the symbols referencing the requested symbol
    """
    return vim.lua.NvimMcpServer.find_referencing_symbols(name_path, relative_path)


@mcp.tool()
def replace_symbol_body(name_path: str, relative_path: str, body: str) -> dict:
    """
    Replaces the full definition of a symbol.

    :param name_path: the name path of the symbol to replace (e.g. "MyClass/my_method")
    :param relative_path: the relative path to the file containing the symbol
    :param body: the new symbol body (the definition including the signature line)
    :return: result summary indicating success or failure
    """
    return vim.lua.NvimMcpServer.replace_symbol_body(name_path, relative_path, body)


@mcp.tool()
def insert_after_symbol(name_path: str, relative_path: str, body: str) -> dict:
    """
    Inserts content after the end of the definition of a given symbol.

    :param name_path: name path of the symbol after which to insert content
    :param relative_path: the relative path to the file containing the symbol
    :param body: the body/content to be inserted
    :return: result summary indicating success or failure
    """
    return vim.lua.NvimMcpServer.insert_after_symbol(name_path, relative_path, body)


@mcp.tool()
def insert_before_symbol(name_path: str, relative_path: str, body: str) -> dict:
    """
    Inserts content before the beginning of the definition of a given symbol.

    :param name_path: name path of the symbol before which to insert content
    :param relative_path: the relative path to the file containing the symbol
    :param body: the body/content to be inserted
    :return: result summary indicating success or failure
    """
    return vim.lua.NvimMcpServer.insert_before_symbol(name_path, relative_path, body)


@mcp.tool()
def rename_symbol(name_path: str, relative_path: str, new_name: str) -> dict:
    """
    Renames a symbol throughout the codebase using language server refactoring.

    :param name_path: name path of the symbol to rename (e.g. "MyClass/my_method")
    :param relative_path: the relative path to the file containing the symbol
    :param new_name: the new name for the symbol
    :return: result summary indicating success or failure
    """
    return vim.lua.NvimMcpServer.rename_symbol(name_path, relative_path, new_name)


@mcp.tool()
def format(relative_path: str) -> dict:
    """
    Formats a file using the language server.

    :param relative_path: the relative path to the file to format
    :return: result summary indicating success or failure
    """
    return vim.lua.NvimMcpServer.format(relative_path)


@mcp.tool()
def restart_language_server() -> dict:
    """
    Restarts the LSP server. This may be necessary when edits not through MCP happen.

    :return: result summary indicating success or failure
    """
    return vim.lua.NvimMcpServer.restart_language_server()


@mcp.tool()
def get_lsp_client_info() -> dict:
    """
    Get information about the active LSP clients.

    :return: a dict containing information about active LSP clients
    """
    return vim.lua.NvimMcpServer.get_lsp_client_info()


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="nvim-mcp-server")
    parser.add_argument("-v", "--version",
                        action="store_true", help="Show version")
    args, _ = parser.parse_known_args()

    if args.version:
        print("nvim-mcp-server v0.1.0")
        sys.exit(0)

    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()

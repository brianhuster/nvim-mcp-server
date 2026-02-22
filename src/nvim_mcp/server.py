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
    instructions="""
    If you see this MCP server, it means your user is using Neovim. You can use
    tools provided by this server to interact with the Neovim instance the user
    is using. This server also provides tools to use some language server
    protocol features, such as getting diagnostics and symbols, formatting code
    """,
)


PLUGIN_PATH = os.path.join(
    dirname(dirname(dirname(os.path.abspath(__file__)))),
    "plugin",
    "nvim-mcp-server.lua",
)
print(PLUGIN_PATH)

vim.command(f"luafile {PLUGIN_PATH}")


@mcp.tool()
def execute_vimscript(code: str) -> str:
    """
    Execute Vimscript code in the Neovim instance and return the output.

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

    Only statements are executed.

    :param code: The Lua code to execute. To evaluate an expression, prefix it
    with "return": `return my_function(...)`
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

    Use this tool to get information about errors, warnings, and other
    diagnostics reported by the language server. This should be called after
    performing edits to check for any new issues or to verify that existing
    issues have been resolved.

    :param relative_path: Optional. The relative path to the file to get
    diagnostics for. If not provided, diagnostics for all open files will be
    returned.
    """
    try:
        return vim.lua.NvimMcpServer.get_diagnostics(relative_path)
    except Exception as e:
        return f"INTERNAL ERROR: {type(e).__name__}: {e}"


@mcp.tool()
def get_document_symbols(relative_path) -> str:
    """
    Use this tool to get a high-level understanding of the code symbols in a
    file. This should be the first tool to call when you want to understand a
    new file, unless you already know what you are looking for.

    :param relative_path: the relative path to the file to get the overview of
    """
    try:
        return vim.lua.NvimMcpServer.get_document_symbols(relative_path)
    except Exception as e:
        return f"INTERNAL ERROR: {type(e).__name__}: {e}"


@mcp.tool()
def get_workspace_symbols(query: str, include_external: bool) -> str:
    """
    Use this tool to search for symbols across the entire workspace. This is
    useful when you are learning about the overall structure of the codebase or
    when you are looking for a specific symbol but don't know where it is
    defined.

    :param query: the query string to search for in the workspace symbols. If
    no query is provided, all symbols in the workspace will be returned.
    :param include_external: optional boolean to include symbols from libraries
    outside the current working directory. Defaults to false.
    """
    try:
        return vim.lua.NvimMcpServer.get_workspace_symbols(query)
    except Exception as e:
        return f"INTERNAL ERROR: {type(e).__name__}: {e}"


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="nvim-mcp-server")
    parser.add_argument("-v", "--version", action="store_true", help="Show version")
    args, _ = parser.parse_known_args()

    if args.version:
        print("nvim-mcp-server v0.1.0")
        sys.exit(0)

    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()

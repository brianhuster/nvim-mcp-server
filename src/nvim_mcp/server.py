import sys
import os

from fastmcp import FastMCP
from pynvim import attach

NVIM = os.environ.get("NVIM")
if not NVIM:
    raise RuntimeError("$NVIM environment variable is not set")
vim = attach("socket", path=NVIM)

mcp = FastMCP(
    name="nvim-mcp-server",
    instructions="This is an MCP that allows you to control a Nvim instance"
)

# Get paths to directory of this file
dir = os.path.dirname(os.path.abspath(__file__))


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

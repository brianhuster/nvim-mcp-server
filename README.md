[![MseeP.ai Security Assessment Badge](https://mseep.net/pr/brianhuster-nvim-mcp-server-badge.png)](https://mseep.ai/app/brianhuster-nvim-mcp-server)

# Neovim MCP Server

A Model Context Protocol (MCP) server for Neovim that provides LSP-based symbol tools. This server enables AI language models to interact with Neovim's Language Server Protocol (LSP) for symbol-level code operations.

## Features

### Symbol Tools (LSP-based)

- `get_symbols_overview(relative_path, depth)` - Get overview of top-level symbols in a file. Use `depth` to include children (e.g., methods of a class).
- `find_symbol(name_path_pattern, relative_path, depth)` - Find symbols by name path pattern (e.g., "MyClass/my_method").
- `find_referencing_symbols(name_path, relative_path)` - Find all references to a symbol.
- `replace_symbol_body(name_path, relative_path, body)` - Replace the body of a symbol definition.
- `insert_after_symbol(name_path, relative_path, body)` - Insert content after a symbol's definition.
- `insert_before_symbol(name_path, relative_path, body)` - Insert content before a symbol's definition.
- `rename_symbol(name_path, relative_path, new_name)` - Rename a symbol throughout the codebase.
- `restart_language_server()` - Restart the LSP server (useful when LSP hangs).
- `get_lsp_client_info()` - Get information about active LSP clients.

### General Tools

- `execute_lua(code)` - Execute Lua code in Neovim
- `execute_vimscript(code)` - Execute Vimscript code in Neovim

## Installation

### Prerequisites

- Python 3.11+
- [uv](https://github.com/astral-sh/uv) package manager
- Neovim 0.9+ with built-in LSP client

### Install from source

```bash
git clone https://github.com/brianhuster/nvim-mcp-server.git
cd nvim-mcp-server
uv sync
```

### Add to your Neovim configuration

Add the plugin directory to your Neovim runtime path:

```lua
-- In your init.lua or plugins.lua
vim.opt.runtimepath:append("/path/to/nvim-mcp-server/plugin")
```

## Usage

### Start Neovim with the MCP server

1. Start Neovim with a socket:
   ```bash
   nvim --listen /tmp/nvim.sock
   ```

2. Set the NVIM environment variable and run the MCP server:
   ```bash
   export NVIM=/tmp/nvim.sock
   uv run nvim-mcp
   ```

### Configuration with Claude Desktop

Add this to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "nvim": {
      "command": "uv",
      "args": ["run", "nvim-mcp"],
      "env": {
        "NVIM": "/tmp/nvim.sock"
      }
    }
  }
}
```

### Use with Goose

```yaml
extensions:
  nvim-mcp:
    cmd: uv
    args: ["run", "nvim-mcp"]
    env:
      NVIM: "/tmp/nvim.sock"
    type: stdio
```

## Development

### Commands

- `uv run nvim-mcp` - Start the MCP server
- `uv run nvim-mcp --version` - Show version
- `uv run ruff check` - Run linting
- `uv run mypy` - Run type checking

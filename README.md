# Neovim MCP Server

A Model Context Protocol (MCP) server for Neovim that provides enhanced integration between language models and Neovim. This server enables AI language models to interact with Neovim, execute commands, read buffer contents, access Vim's help system, and more.

## Installation

This project is currently in very early development, so there is no stable release yet. For now, you have to install from source

```bash
git clone --depth=1 https://github.com/brianhuster/nvim-mcp-server.git
cd nvim-mcp-server
npm install -g .
```

The CLI can then be called with `nvim-mcp` command.

## Usage

### Use with [goose](https://github.com/block/goose)

This server was originally created to use with Goose AI agent. Use the following config to integrate with Goose:

```yaml
extensions:
  nvim-mcp:
    args: []
    bundled: null
    cmd: nvim-mcp
    description: An extension to control a Neovim instance. Use it to execute commands, read buffer contents, get LSP diagnostics, read help, man pages,...
    enabled: true
    env_keys: []
    envs: {}
    name: nvim-mcp
    timeout: 300
    type: stdio
```

#!/usr/bin/env node

import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, resolve } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

const packageJson = JSON.parse(
	readFileSync(resolve(__dirname, '../package.json'), 'utf8')
);

const args = process.argv.slice(2);
if (args.includes('-v') || args.includes('--version')) {
	console.log(`nvim-mcp v${packageJson.version}`);
	process.exit(0);
}

if (args.includes('-h') || args.includes('--help')) {
	console.log(`
nvim-mcp - An MCP server for Neovim

Usage:
  nvim-mcp [options]

Options:
  -v, --version     Show version information
  -h, --help        Show this help message

Description:
  nvim-mcp is a Model Context Protocol (MCP) server that provides enhanced
  integration between language models and Neovim. It enables execution of
  Vim commands, reading buffer contents, accessing Vim's help system,...
`);
	process.exit(0);
}

import { McpServer, ResourceTemplate } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import * as nvim from './utils/nvim.js';

const vim = nvim.nvim;

const server = new McpServer({
	name: "nvim-mcp-server",
	version: "0.1.0"
});

server.resource(
	"current-buffer",
	new ResourceTemplate("nvim://buffer", {
		list: () => ({
			resources: [{
				uri: "nvim://buffer",
				mimeType: "text/plain",
				name: "Current buffer",
				description: "Get name and content of current buffer"
			}]
		})
	}),
	async (uri) => {
		const buf = vim.buffer
		const bufname = await buf.name
		const lines = await buf.lines
		return {
			contents: [{
				uri: uri.href,
				text: `
>> Buffer name: ${bufname}

>> Buffer content:
${lines.join('\n')}
			`
			}]
		}
	}
);

server.resource(
	"current-buffer-diagnostics",
	new ResourceTemplate("nvim://buffer-diagnostics", {
		list: () => ({
			resources: [{
				uri: "nvim://buffer-diagnostics",
				mimeType: "application/json",
				name: "Current buffer diagnostics",
				description: "Get diagnostics for current buffer"
			}]
		}),
	}),
	async (uri) => {
		const diagnostics = await nvim.getDiagnosticsFromBuf(0);
		return {
			contents: [{
				uri: uri.href,
				text: JSON.stringify(diagnostics, null, 2)
			}]
		}
	}
);

server.tool("command",
	{
		cmd: z.string().describe("Vimscript command to execute.\n" +
			"To run Lua code, use `:lua` command, for example: `:lua print('Hello')`\n" +
			"To run shell commands and get its result, use `!`, followed by the command, for example `!ls`\n" +
			"To get completion for a command, use tool `command-completion`")
	},
	async ({ cmd }) => {
		const confirmation = await nvim.confirm(`Execute command: ${cmd}?`);
		if (confirmation !== 1) { // User selected "No"
			return {
				content: [{
					type: "text",
					text: "Operation cancelled by user"
				}]
			};
		}
		return {
			content: [{
				type: "text",
				text: String(await vim.commandOutput(cmd))
			}]
		}
	}
);

server.tool("command-completion",
	{
		cmd: z.string().describe("Command to get completion")
	},
	async ({ cmd }) => {
		const completion = await nvim.getCompletion(cmd, 'cmdline');
		return {
			content: [{
				type: "text",
				text: completion.join('\n')
			}]
		}
	}
)

server.tool(
	"get-diagnostics",
	{
		file: z.string().describe("File to get diagnostics for")
	},
	async ({ file }) => {
		let result = await nvim.getDiagnosticsFromBuf(file);
		result = JSON.stringify(result, null, 2);
		return {
			content: [{
				type: "text",
				text: String(result)
			}]
		};
	}
)

server.tool(
	"get-help",
	{
		tag: z.string().describe("Help tag to get help for. " +
			"If you don't know the exact tag, you can use tool `get-help-tags-completion` to get a list of possible help tags matching a pattern"),
		lines: z.number().describe("Number of document lines to return").optional(),
	},
	async ({ tag, lines }) => {
		const error: string = await vim.call('execute', [`help ${tag}`, 'silent']);
		if (error) {
			return {
				content: [{
					type: "text",
					text: error
				}]
			}
		}
		const win = await vim.window.id
		const text = await nvim.getWinText(win, lines);
		return {
			content: [{
				type: "text",
				text: text
			}]
		}
	}
)

server.tool(
	"get-help-tags-completion",
	{
		tag: z.string().describe("pattern to get help tags completion"),
	},
	async ({ tag }) => {
		return {
			content: [{
				type: "text",
				text: await nvim.getCompletion(tag, 'help').then(res => res.join('\n'))
			}]
		};
	}
)

server.tool(
	"read-man-page",
	{
		name: z.string().describe("name of the man page. " +
			"If you don't know the exact name, you can use tool `get-man-page-completion` to get a list of possible man pages matching a pattern"),
	},
	async ({ name }) => {
		const error: string = await nvim.execute(`Man ${name}`, 'silent');
		if (error) {
			return {
				content: [{
					type: "text",
					text: error
				}]
			}
		}
		const lines = await vim.buffer.lines;
		return {
			content: [{
				type: "text",
				text: lines.join('\n')
			}]
		};
	}
)

server.tool(
	"get-man-page-completion",
	{
		name: z.string().describe("pattern to get man page completion"),
	},
	async ({ name }) => {
		return {
			content: [{
				type: "text",
				text: await nvim.getCompletion(`Man ${name}`, 'cmdline').then(res => res.join('\n'))
			}]
		};
	}
)

// Start receiving messages on stdin and sending messages on stdout
const transport = new StdioServerTransport();
await server.connect(transport);

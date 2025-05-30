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
import { exec } from 'child_process';
import { promisify } from 'util';

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
				description: "Get name and content and diagnostics of current buffer"
			}]
		})
	}),
	async (uri) => {
		const buf = vim.buffer
		const bufname = await buf.name
		const bufnr = await buf.id
		const lines = await buf.lines
		const getOption = await buf.getOption
		const ft = await getOption("filetype")
		const content = lines.map((line, i) => `${i+1} | ${line}`).join('\n')
		const diagnostics = await nvim.getDiagnosticsFromBuf(0);
		const diagnosticText = diagnostics.map(d => `**Line ${d.line}:**\n${d.severity}: ${d.message}. ${d.source ? `Source: ${d.source}` : ''}`).join('\n\n');
		return {
			contents: [{
				uri: uri.href,
				text: `
>> Buffer information:
Name: ${bufname}
Number: ${bufnr}

>> Buffer content:
\`\`\`${ft}
${content}
\`\`\`

>> Buffer diagnostics:
\`\`\`text
${diagnosticText}
\`\`\`
			`
			}]
		}
	}
);

server.resource(
	"list-buffers",
	new ResourceTemplate("nvim://list-buffers", {
		list: () => ({
			resources: [{
				uri: "nvim://list-buffers",
				mimeType: "text/plain",
				name: "List of buffers",
				description: "Get list of buffers. Each line is in the format of <buffer-id>: <buffer-name>"
			}]
		})
	}),
	async () => {
		const bufs = await vim.buffers.then(bufs => bufs.filter(buf => buf.loaded))
		const lines = await Promise.all(bufs.map(async buf => {
			const name = await buf.name
			return `${buf.id}: ${name}`
		})).then(results => results.join('\n'))
		return {
			contents: [{
				uri: "nvim://list-buffers",
				text: lines
			}]
		}
	}
)

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
	"get-help",
	{
		tag: z.string().describe("Help tag to get help for. " +
			"If you don't know the exact tag, you can use tool `get-help-tags-completion` to get a list of possible help tags matching a pattern"),
		lines: z.number().describe("Number of document lines to return").optional(),
	},
	async ({ tag, lines }) => {
		const error: string = await nvim.execute(`help ${tag}`, 'silent');
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

if (await nvim.executable('man')) {
	server.resource(
		"man-page",
		new ResourceTemplate("nvim://man/{name}", {
			list: undefined
		}),
		async (uri, { name }) => {
			try {
				const { stdout, stderr } = await promisify(exec)(`man ${name}`);
				if (stderr) {
					return {
						contents: [{
							uri: uri.href,
							text: stderr
						}]
					}
				};
				return {
					contents: [{
						uri: uri.href,
						text: stdout
					}]
				}
			} catch (error) {
				return {
					contents: [{
						uri: uri.href,
						text: `Failed to execute man command: ${error instanceof Error ? error.message : String(error)}`
					}]
				}
			}
		}
	)

	server.resource(
		"man-search",
		new ResourceTemplate("nvim://man-search/{pattern}", {
			list: undefined
		}),
		async (uri, { pattern }) => {
			const search = await nvim.getCompletion(`Man ${pattern}`, 'cmdline');
			return {
				contents: [{
					uri: uri.href,
					text: search.join('\n')
				}]
			}
		}
	);
}

// Start receiving messages on stdin and sending messages on stdout
const transport = new StdioServerTransport();
await server.connect(transport);

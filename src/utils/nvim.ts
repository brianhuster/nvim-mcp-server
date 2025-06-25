import { attach } from 'neovim';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

interface Diagnostic {
	message: string;
	line_number: number;
	line_content: string;
	severity: "Error"|"Hint"|"Information"|"Warning";
	source?: string;
}

const $NVIM = process.env.NVIM;
if (!$NVIM) {
	console.log('$NVIM environment variable is not set');
	process.exit(0);
}

const vim = attach({ socket: $NVIM });

// import * as child_process from 'node:child_process';
// const progpath = await vim.getVvar("progpath") as string;
// const argv = await vim.getVvar("argv") as string[];
// const vim2_proc = child_process.spawn(progpath, argv.slice(1), {});
// const vim2 = attach({ proc: vim2_proc });

const __dirname = dirname(fileURLToPath(import.meta.url));
vim.lua(readFileSync(`${__dirname}/../../plugin/nvim-mcp-server.lua`, 'utf8'));

export const nvim = vim;

/*
 * TODO: Handle the case when the Lua function returns an error
 */
export const getDiagnosticsFromBuf = async (file: string|number): Promise<Diagnostic[]> => {
	return vim.lua("return NvimMcpServer.get_diagnostics_from_file(...)", [file]) as Promise<Diagnostic[]>;
}

export const getWinText = async (win: number, lines?: number): Promise<any> => {
	return vim.lua("return NvimMcpServer.get_win_text(...)", lines ? [win, lines] : [win]);
}

export const getCompletion = (pat: string, type: string): Promise<string[]> => {
	return vim.call('getcompletion', [pat, type])
}

export const execute = (cmd: string, silent: ''|'silent'|'silent!'): Promise<string> => {
	return vim.call('execute', [cmd, silent]);
}

export const confirm = (message: string): Promise<number> => {
	return vim.call('confirm', ["Nvim MCP server: " + message, "&Yes\n&No"]);
}

export const executable = (cmd: string): Promise<number> => {
	return vim.call('executable', [cmd]);
}

export const getcwd = (): Promise<string> => {
	return vim.call('getcwd');
}

export const bufnr = (buf: number|string, create: boolean): Promise<number> => {
	return vim.call('bufnr', [buf, create]);
}

export const bufGetName = (buf: number): Promise<string> => {
	return vim.request('bufname', [buf]);
}

import { attach } from 'neovim';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

interface Diagnostic {
	message: string;
	line: number;
	severity: number;
	source?: string;
}

const $NVIM = process.env.NVIM;
if (!$NVIM) {
	console.log('$NVIM environment variable is not set');
	process.exit(0);
}

const vim = attach({ socket: $NVIM });

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
	return vim.call('confirm', [message, "&Yes\n&No"]);
}

export const executable = (cmd: string): Promise<number> => {
	return vim.call('executable', [cmd]);
}

export const getcwd = (): Promise<string> => {
	return vim.call('getcwd');
}

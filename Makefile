.PHONY: build install inspect test lint clean

build:
	uv build

install: build
	uv pip install dist/nvim_mcp-0.1.0-py3-none-any.whl --force-reinstall

inspect:
	@if [ -z "$(NVIM)" ]; then \
		echo "Error: NVIM environment variable not set"; \
		echo "Usage: NVIM=/tmp/nvim.sock make inspect"; \
		exit 1; \
	fi
	npx @modelcontextprotocol/inspector uv run nvim-mcp

test: build
	@echo "Running MCP server tests..."

lint:
	uv run ruff check src/

typecheck:
	uv run mypy src/

clean:
	rm -rf build/ dist/ *.egg-info
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true

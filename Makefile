SHELL := /bin/bash

# Default configuration
# The scheme for the CLI package is typically "brain-cli" (the package name)
SCHEME_CLI := brain-cli
SCHEME_APP := BrainOS
CONFIG := Release
PROJECT := App/BrainOS.xcodeproj
DERIVED := build/DerivedData

.PHONY: help cli app install-cli serve status clean

help:
	@echo "Targets:"
	@echo "  cli          Build CLI ($(SCHEME_CLI)) into $(DERIVED)"
	@echo "  app          Build app ($(SCHEME_APP)) and embed CLI"
	@echo "  install-cli  Install/update /usr/local/bin/brainos symlink"
	@echo "  serve        Build CLI and start server (use PORT=XXXX, EXPOSE=1)"
	@echo "  status       Check if server is running"
	@echo "  clean        Remove DerivedData build output"

cli:
	@echo "Building CLI ($(SCHEME_CLI))…"
	xcodebuild -project $(PROJECT) -scheme $(SCHEME_CLI) -configuration $(CONFIG) -derivedDataPath $(DERIVED) build -quiet

app: cli
	@echo "Building app ($(SCHEME_APP))…"
	xcodebuild -project $(PROJECT) -scheme $(SCHEME_APP) -configuration $(CONFIG) -derivedDataPath $(DERIVED) build -quiet
	@echo "Embedding CLI into App Bundle (Helpers)…"
	# Copy brain-cli to BrainOS.app/Contents/Helpers/brainos
	mkdir -p "$(DERIVED)/Build/Products/$(CONFIG)/BrainOS.app/Contents/Helpers"
	cp "$(DERIVED)/Build/Products/$(CONFIG)/brain-cli" "$(DERIVED)/Build/Products/$(CONFIG)/BrainOS.app/Contents/Helpers/brainos"
	chmod +x "$(DERIVED)/Build/Products/$(CONFIG)/BrainOS.app/Contents/Helpers/brainos"

install-cli: cli
	@echo "Installing CLI symlink…"
	./scripts/install_cli_symlink.sh --dev

serve: install-cli
	@echo "Starting BrainOS server…"
	@if [[ -n "$(PORT)" ]]; then \
		ARGS="$$ARGS --port $(PORT)"; \
	fi; \
	if [[ "$(EXPOSE)" == "1" ]]; then \
		ARGS="$$ARGS --expose"; \
	fi; \
	brainos serve $$ARGS

status:
	brainos status

clean:
	rm -rf $(DERIVED)
	@echo "Cleaned $(DERIVED)"

# Patch MLX-swift-lm to fix Message type ambiguity (run after swift package resolve)
patch-mlx:
	@echo "Patching MLX-swift-lm..."
	./scripts/patch_mlx.sh

# Resolve packages and apply patches
resolve:
	cd Packages/BrainCore && swift package resolve
	./scripts/patch_mlx.sh

# Build BrainCore with patches
build-core: resolve
	cd Packages/BrainCore && swift build

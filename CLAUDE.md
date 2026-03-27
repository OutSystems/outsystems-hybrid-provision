# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture and Design

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the system boundary diagram, external integrations table, ring-based environment isolation tenet, and ECR Public registry strategy.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for branch naming conventions (`RDSHDT-<ticket>`), commit message format, PR workflow with automatic gh-pages preview deployment, and manual testing process.

## Repository Structure

```
scripts/
  linux-installer.sh      # Bash installer for Linux (~32K)
  macos-installer.sh      # Bash installer for macOS (~32K)
  windows-installer.ps1   # PowerShell installer for Windows (~42K)
.github/workflows/
  pr-release.yml          # PR preview: publishes dev-ring scripts to gh-pages/pr/
  main-release.yml        # Main deploy: publishes all rings to gh-pages/<ring>/, creates GitHub Release
```

There is no build step, compiled output, package.json, Makefile, or test suite. The three scripts in `scripts/` are the deliverables.

## Key Commands

```bash
# Run the Linux installer locally against a cluster
./scripts/linux-installer.sh --operation=install --env=dev

# Uninstall
./scripts/linux-installer.sh --operation=uninstall

# Get SHO console URL
./scripts/linux-installer.sh --operation=get-console-url

# Windows equivalent
.\scripts\windows-installer.ps1 -operation install -env dev
```

There are no lint, format, or automated test commands. Validation is manual against a live Kubernetes or OpenShift cluster.

## Important Conventions

### Three-platform parity

The Linux, macOS, and Windows scripts must stay functionally aligned. Any feature or flag added to one script should be reflected in the other two. The Bash scripts (Linux and macOS) are nearly identical; differences are limited to OS-specific dependency installation.

### Script configuration pattern

Each script defines its tunable defaults as variables at the top of the file (`DEFAULT_ENV`, `DEFAULT_OPERATION`, `DEFAULT_USE_ACR`, `DEFAULT_PEGASUS_ENABLED`, `DEFAULT_KEVENTS_REPLICAS`). CI pipelines modify `DEFAULT_ENV` via `sed` replacement to produce per-ring copies -- never hardcode ring-specific values in the source scripts.

### Logging functions

All user-facing output must go through the existing logging helpers: `log_info`, `log_success`, `log_warning`, `log_error`, `log_step`. These provide colored, emoji-prefixed output. In the PowerShell script, equivalent `Write-*` wrapper functions exist.

### ECR alias constants

Each environment ring maps to a distinct ECR alias constant (`ECR_ALIAS_GA`, `ECR_ALIAS_EA`, `ECR_ALIAS_TEST`, `ECR_ALIAS_DEV`). The `setup_environment` function selects the correct alias based on the `ENV` variable. See [ARCHITECTURE.md](./ARCHITECTURE.md) for the T3 tenet on ECR Public as the canonical registry.

### The `--use-acr` flag is a temporary shim

ACR support exists only for backward compatibility and is off by default. See the "ACR backward compatibility" phase constraint in [ARCHITECTURE.md](./ARCHITECTURE.md) for expiration criteria.

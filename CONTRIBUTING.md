# Contributing to outsystems-hybrid-provision

## Overview

This repository contains installer scripts (Bash and PowerShell) for the OutSystems Self-Hosted Operator (SHO). There is no compiled language or build step -- the deliverables are the shell scripts in `scripts/`.

## Development Setup

### Prerequisites

- Git
- A Bash-compatible shell (Linux/macOS) or PowerShell (Windows)
- Access to a Kubernetes (>= 1.28) or OpenShift (>= 4.15.9) cluster for end-to-end testing
- `helm` CLI installed (the installer scripts invoke Helm)

### Clone and verify

```bash
git clone git@github.com:OutSystems/outsystems-hybrid-provision.git
cd outsystems-hybrid-provision
```

There is no build or install step. The scripts under `scripts/` are the source of truth.

## Repository Structure

```
scripts/
  linux-installer.sh      # Bash installer for Linux
  macos-installer.sh      # Bash installer for macOS
  windows-installer.ps1   # PowerShell installer for Windows
.github/workflows/
  pr-release.yml          # Publishes PR preview scripts to gh-pages
  main-release.yml        # Deploys ring-specific scripts and creates a GitHub Release
```

## Development Workflow

### Branch naming

Branches follow the pattern `RDSHDT-<ticket>` or `RDSHDT-<ticket>-<short-description>`, matching Jira ticket IDs. Examples from this repository:

```
RDSHDT-2107-ea-release
RDSHDT-1980-support-pegasus-flag
RDSHDT-1943-enable-ring
```

### Commit messages

Prefix commit messages with the Jira ticket ID followed by a colon and a brief description:

```
RDSHDT-1943: Enable ring in scripts
RDSHDT-1980: Support Pegasus Flag
```

### Pull requests

1. Create a branch from `main` using the naming convention above.
2. Make changes to the relevant scripts in `scripts/`.
3. Open a PR targeting `main`.
4. The **PR Preview Release** workflow automatically publishes your modified scripts to the `gh-pages` branch under the `pr/` directory with `DEFAULT_ENV` set to `dev`. A bot comment provides curl/irm one-liners you can use to test.
5. After review and merge, the **Main Branch Ring Deployment** workflow deploys scripts across all environment rings (dev, test, ea, ga) and creates a GitHub Release.

### Environment rings

The installer scripts support four environment rings, each pointing to a different ECR alias:

| Ring | Purpose |
|------|---------|
| `dev` | Development |
| `test` | Testing |
| `ea` | Early Access |
| `ga` | General Availability (production default) |

The `DEFAULT_ENV` variable in each script controls which ring is used by default. CI modifies this value per ring during deployment -- do not hardcode ring-specific values in the source scripts.

## Testing

There is no automated test suite. Before submitting a PR, manually verify your changes:

1. Run the relevant installer script locally against a test cluster.
2. Use the PR preview scripts (deployed automatically by CI) to validate in the `dev` environment.
3. Test all three platform scripts (Linux, macOS, Windows) if your change affects shared logic.

## Code Standards

### Shell scripts (Bash)

- Scripts use `set -e` to fail on errors.
- Use the existing logging functions (`log_info`, `log_success`, `log_warning`, `log_error`, `log_step`) for user-facing output.
- Keep the three platform scripts (Linux, macOS, PowerShell) functionally aligned -- a feature added to one should be reflected in the others.

### Script configuration

- Default values are defined as variables at the top of each script (e.g., `DEFAULT_ENV`, `DEFAULT_OPERATION`).
- Environment-specific ECR aliases are maintained as constants near the top of the script.

## CI/CD

| Trigger | Workflow | What it does |
|---------|----------|--------------|
| PR opened/updated (changes in `scripts/`) | `pr-release.yml` | Publishes preview scripts to `gh-pages/pr/` with `dev` default |
| Push to `main` (changes in `scripts/`) | `main-release.yml` | Deploys all rings to `gh-pages/<ring>/` and creates a GitHub Release |

Both workflows only trigger when files under `scripts/` or the workflow file itself are modified.

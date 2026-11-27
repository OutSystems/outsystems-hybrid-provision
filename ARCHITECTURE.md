# outsystems-selfhosted-provision Architecture

> **Repository:** outsystems-selfhosted-provision
> **Runtime Environment:** CLI tool (operator's workstation)
> **Last Updated:** 2026-03-26

## Overview

This repository hosts platform-specific installer scripts (Linux, macOS, Windows) that provision the OutSystems Self-Hosted Operator (SHO) onto a customer's Kubernetes or OpenShift cluster. The scripts run on an operator's local machine and orchestrate Helm-based installation of the SHO operator, which then manages the self-hosted ODC platform (Hybrid and FRSH tenants) within the customer's infrastructure.

## Architecture Diagram

```mermaid
graph TB
    ThisRepo["outsystems-selfhosted-provision<br/>Runs on: Operator's Workstation (CLI)"]

    ECR["AWS ECR Public Registry<br/>(public.ecr.aws)<br/>EXTERNAL"]
    K8s["Kubernetes / OpenShift Cluster<br/>EXTERNAL"]
    GHPages["GitHub Pages<br/>(outsystems.github.io)<br/>EXTERNAL"]
    KubeDL["Kubernetes Release Server<br/>(dl.k8s.io)<br/>EXTERNAL"]
    HelmGH["Helm Install Script<br/>(raw.githubusercontent.com)<br/>EXTERNAL"]

    GHPages -->|"HTTP download<br/>Synchronous"| ThisRepo
    ThisRepo -->|"OCI / HTTP REST<br/>Synchronous"| ECR
    ThisRepo -->|"kubectl & helm CLI<br/>Synchronous"| K8s
    ThisRepo -->|"HTTP download<br/>Synchronous"| KubeDL
    ThisRepo -->|"HTTP download<br/>Synchronous"| HelmGH

    classDef thisRepo fill:#e0f2f1,stroke:#00796b,stroke-width:3px
    classDef external fill:#ffe1e1,stroke:#d32f2f,stroke-width:2px,stroke-dasharray: 5 5
    classDef database fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px

    class ThisRepo thisRepo
    class ECR,K8s,GHPages,KubeDL,HelmGH external
```

## External Integrations

| External Service | Communication Type | Purpose |
|---|---|---|
| AWS ECR Public Registry (`public.ecr.aws`) | Sync (OCI/HTTP REST) | Pull Helm charts and container images for each ring (dev/test/ea/ga) |
| Kubernetes / OpenShift Cluster | Sync (kubectl, helm CLI) | Deploy SHO operator via Helm, manage namespaces, pods, port-forwarding |
| GitHub Pages (`outsystems.github.io`) | Sync (HTTP) | Distribute installer scripts to end users via curl/irm one-liners |
| Kubernetes Release Server (`dl.k8s.io`) | Sync (HTTP) | Auto-install kubectl if missing on operator's machine |
| Helm Install Script (`raw.githubusercontent.com`) | Sync (HTTP) | Auto-install Helm 3 if missing on operator's machine |
| Chocolatey (`community.chocolatey.org`, Windows only) | Sync (HTTP) | Auto-install jq and curl on Windows via package manager |
| GitHub API (`api.github.com`) | Sync (HTTP REST) | Fetch latest Helm release version (Windows installer) |

## Architectural Tenets

### T1. Single-script, zero-dependency installer experience

Each platform (Linux, macOS, Windows) ships a single self-contained script that auto-detects and installs all prerequisites (kubectl, helm, jq, curl). The user should never need to manually install tooling before running the installer. This lowers the barrier to adoption for customers who may not have a pre-configured workstation.

**Evidence:**
- `scripts/negative/linux-installer.sh` (in `check_dependencies`) - automatically installs kubectl, helm, jq, and curl if missing
- `scripts/negative/windows-installer.ps1` (in dependency checks) - installs Chocolatey, then uses it for jq/curl, downloads kubectl and helm binaries directly

### T2. Ring-based environment isolation with identical script structure

The installers live in two folders. `scripts/negative/` holds the scripts for the internal rings (dev, test, stage), which carry options customers must not see: `--pegasus-enabled`, `--kevents-replicas`, `--sh-monitoring` and the dev/test/stage ECR aliases. `scripts/positive/` holds the scripts for ea and ga, which contain none of that: not hidden from `--help`, but absent from the source a customer downloads. Both folders have the same structure and the same behavior apart from the internal options; the CI pipeline only sets `DEFAULT_ENV` per ring. The `Ring Scripts Check` workflow fails a PR if an internal option, variable or alias appears in `scripts/positive/`.

**Evidence:** (paths below are the full scripts in `scripts/negative/`; `scripts/positive/` has the same code without the internal options)
- `scripts/negative/linux-installer.sh` (in `setup_environment`) - switches ECR alias based on `ENV` variable; all other logic is shared
- `.github/workflows/main-release.yml` (in `Prepare ring-specific scripts`) - builds each ring from `scripts/negative/` (dev, test, stage) or `scripts/positive/` (ea, ga) and patches only `DEFAULT_ENV`
- `.github/workflows/ring-scripts-check.yml` - fails a PR when `scripts/positive/` contains an internal name, and shows how `scripts/positive/` differs from `scripts/negative/`
- `.github/workflows/pr-release.yml` (in `Prepare scripts with dev default and a ga preview`) - PR previews are published for the `dev` ring (`pr/`) and as a customer-facing `ga` build (`pr/ga/`)

### T3. ECR Public as the canonical artifact registry

All Helm charts and container images are pulled from AWS ECR Public (`public.ecr.aws`). Each ring has its own ECR alias (e.g., `j0s5s8b0/ga`, `m5i8c6m7/ea`). New integrations must target ECR Public.

**Evidence:**
- `scripts/negative/linux-installer.sh` (in global constants) - `PUB_REGISTRY="public.ecr.aws"` with per-ring `ECR_ALIAS_*` variables

### T4. GitHub Pages as the distribution channel for installer scripts

Installer scripts are not distributed via package managers or binary releases. Instead, the CI pipeline publishes them to GitHub Pages, enabling one-liner curl-pipe-bash (or `irm | iex` on Windows) installation. The `gh-pages` branch is the deployment target, and the index page provides per-ring download links.

**Evidence:**
- `.github/workflows/main-release.yml` (in `Deploy to ring directories`) - copies ring scripts to `gh-pages/` branch
- `.github/workflows/main-release.yml` (in `Create index page`) - generates HTML with download links and one-liner install commands
- `.github/workflows/pr-release.yml` (in `Deploy to PR directory`) - PR previews also go to `gh-pages/pr/`

### T5. Helm upgrade-install as the sole deployment mechanism

The scripts use `helm upgrade --install` exclusively for deploying the SHO operator. There is no direct manifest application, no Kustomize, and no custom resource creation outside of Helm. This ensures that Helm is the single source of truth for the deployed state, making rollback and version management straightforward.

**Evidence:**
- `scripts/negative/linux-installer.sh` (in `sho_install`) - uses `helm upgrade --install` with `--create-namespace` for idempotent deployment
- `scripts/negative/linux-installer.sh` (in `sho_uninstall`) - uses `helm uninstall` as the primary teardown, with kubectl only for finalizer cleanup

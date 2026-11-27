# outsystems-selfhosted-provision
Self hosted version of ODC

> **Renamed.** This repository was previously called `outsystems-hybrid-provision`. The name is now generic because the installers serve both Hybrid and FRSH tenants. See [Migrating from the old name](#migrating-from-the-old-name).


## Table of Contents
1. [Overview](#overview)
2. [Key Features](#key-features)
3. [System Requirements](#system-requirements)
4. [Usage](#usage)
5. [Migrating from the old name](#migrating-from-the-old-name)


## Overview

The outsystems-selfhosted-provision repository hosts the installation setup for the self-hosted version of outsystems ODC product.

The self-hosted ODC product is a low-code application development platform that enables your applications and data to host on your infrastructure (private cloud or on-premises). This Hybrid Low-Code Platform, a next-generation application development platform designed for enterprises that need the speed of low-code development with the control of on-premises data management.

Unlike fully cloud-hosted platforms, this solution offers the flexibility to run critical workloads on your infrastructure, while seamlessly integrating with cloud-based services for centralized control, updates, and monitoring.

It supports both Openshift and Kubernetes. However, the build and deploy of the applications will still remain with Outsystems ODC. ODC Portal and ODC Studio work together, making it quick to get the tools you need to develop and deploy your apps.

Before you can use ODC Studio, download it from the ODC Portal and login to your Outsystems tenant.


## Key Features

    Hybrid Deployment Model

        Core services deployed in the customer's environment (on-prem or private cloud)

    Customer-Owned Data

        All application and user data is stored and processed within the customer's controlled environment

    Low-Code Development Experience

        Drag-and-drop visual builder

        Pre-built templates and integrations

        Reusable components and custom code support


## System Requirements

For the setup of the self-hosted operator, the cluster must meet the following requirements:

1. At least 4 worker nodes
2. Minimum of 4 CPU Cores per worker node
3. Minimum of 4 GB RAM per worker node
4. OpenShift version >= 4.15.9* or Kubernetes* >= 1.28
5. Internet connectivity (or whitelist OutSystems domains)

## Usage

The OutSystems Self-Hosted Operator installer provides platform-specific scripts for Linux, macOS, and Windows to automatically install, manage, and configure the self-hosted operator on Kubernetes clusters.

### Platform-Specific Scripts

- **Linux**: `scripts/positive/linux-installer.sh` (customers, rings `ea` and `ga`) and `scripts/negative/linux-installer.sh` (internal rings `dev`, `test`, `stage`)
- **macOS**: `scripts/positive/macos-installer.sh` and `scripts/negative/macos-installer.sh`
- **Windows**: `scripts/positive/windows-installer.ps1` and `scripts/negative/windows-installer.ps1`

### Basic Installation Commands

**Linux/macOS:**
```bash
# Run locally
./scripts/positive/linux-installer.sh --operation=install
```

**Windows PowerShell:**
```powershell
# Run locally
.\scripts\windows-installer.ps1 -operation install
```

### Command-Line Options

#### Linux/macOS Options
```bash
--version=VERSION        # SHO version to install/manage (default: latest)
--env=ENVIRONMENT       # Environment: dev, test, stage, ea, ga (default: ga)
--operation=OPERATION   # Operation: install, uninstall, get-console-url (default: install)
--help, -h              # Show help message
```

#### Windows PowerShell Options
```powershell
--version=VERSION        # SHO version to install/manage (default: latest)
--env=ENVIRONMENT       # Environment: dev, test, stage, ea, ga (default: ga)
--operation=OPERATION   # Operation: install, uninstall, get-console-url (default: install)
--help, -h              # Show help message
```

### Usage Examples

#### Install Latest Version
```bash
# Linux/macOS
./scripts/positive/linux-installer.sh
./scripts/positive/macos-installer.sh

# Windows
.\scripts\windows-installer.ps1
```

#### Install Specific Version
```bash
# Linux/macOS
./scripts/positive/linux-installer.sh --operation=install --version=0.2.3

# Windows
.\scripts\windows-installer.ps1 --operation=install -version 0.2.3 
```

#### Get Console URL
```bash
# Linux/macOS
./scripts/positive/linux-installer.sh --operation=get-console-url

# Windows
.\scripts\windows-installer.ps1 -operation get-console-url
```

#### Uninstall SHO
```bash
# Linux/macOS
./scripts/positive/linux-installer.sh --operation=uninstall

# Windows
.\scripts\windows-installer.ps1 -operation uninstall
```

### Getting Started

Once installation is complete:

1. Access the SHO console via the provided URL (typically `http://localhost:5050`)
2. Log in to your OutSystems tenant
3. Navigate to the Self-Hosted Setup section
4. Follow the tenant-specific configuration instructions
5. Begin deploying applications to your self-hosted environment


## Migrating from the old name

The repository and its GitHub Pages site move from `outsystems-hybrid-provision` to `outsystems-selfhosted-provision`. The installer file names and options do not change.

| | Old | New |
|---|---|---|
| Repository | `OutSystems/outsystems-hybrid-provision` | `OutSystems/outsystems-selfhosted-provision` |
| Installer URL | `https://outsystems.github.io/outsystems-hybrid-provision/<ring>/<installer>` | `https://outsystems.github.io/outsystems-selfhosted-provision/<ring>/<installer>` |

- **Commands copied from the SH Console or from the SH Registration Service** are generated with the current URL. Customers who copy a fresh command after the cutover need to do nothing.
- **Commands saved in scripts, runbooks or pipelines** that use the old Pages URL must be updated to the new URL. GitHub does not redirect Pages URLs after a repository rename.
- **Git remotes** pointing at the old repository keep working (GitHub redirects repository URLs). Update them with `git remote set-url origin git@github.com:OutSystems/outsystems-selfhosted-provision.git`.

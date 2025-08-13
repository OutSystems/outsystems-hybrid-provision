# outsystems-hybrid-provision
Self hosted version of ODC


## Table of Contents
1. [Overview](#overview)
2. [Key Features](#key-features)
3. [System Requirements](#system-requirements)
4. [Usage](#usage)


## Overview

The Outsystems-hybrid-provision hosts the installation setup for the self-hosted version of outsystems ODC product.

Outsystems-hybrid-provision product is a low-code application development platform that enables your applications and data to host on your infrastructure (private cloud or on-premises). This Hybrid Low-Code Platform, a next-generation application development platform designed for enterprises that need the speed of low-code development with the control of on-premises data management.

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

1. At least 3 worker nodes
2. Minimum of 4 CPU Cores per worker node
3. Minimum of 4 GB RAM per worker node
4. OpenShift version >= 4.15.9* or Kubernetes* >= 1.28
5. Internet connectivity (or whitelist OutSystems domains)

## Usage

The OutSystems Self-Hosted Operator installer provides platform-specific scripts for Linux, macOS, and Windows to automatically install, manage, and configure the self-hosted operator on Kubernetes clusters.

### Platform-Specific Scripts

- **Linux**: `scripts/linux-installer.sh`
- **macOS**: `scripts/macos-installer.sh`  
- **Windows**: `scripts/windows-installer.ps1`

### Basic Installation Commands

**Linux/macOS:**
```bash
# Run locally
./scripts/linux-installer.sh --operation=install
```

**Windows PowerShell:**
```powershell
# Run locally
.\scripts\windows-installer.ps1 --operation=install
```

### Command-Line Options

#### Linux/macOS Options
```bash
--version=VERSION        # SHO version to install/manage (default: latest)
--env=ENVIRONMENT       # Environment: prod, non-prod (default: prod)
--operation=OPERATION   # Operation: install, uninstall, get-console-url (default: install)
--help, -h              # Show help message
```

#### Windows PowerShell Options
```powershell
--version=VERSION        # SHO version to install/manage (default: latest)
--env=ENVIRONMENT       # Environment: prod, non-prod (default: prod)
--operation=OPERATION   # Operation: install, uninstall, get-console-url (default: install)
--help, -h              # Show help message
```

### Usage Examples

#### Install Latest Version
```bash
# Linux/macOS
./scripts/linux-installer.sh
./scripts/macos-installer.sh

# Windows
.\scripts\windows-installer.ps1
```

#### Install Specific Version
```bash
# Linux/macOS
./scripts/linux-installer.sh --operation=install --version=0.2.3

# Windows
.\scripts\windows-installer.ps1 --operation=install --version=0.2.3 --env=non-prod 
```

#### Get Console URL
```bash
# Linux/macOS
./scripts/linux-installer.sh --operation=get-console-url

# Windows
.\scripts\windows-installer.ps1 --operation=get-console-url --env=prod
```

#### Uninstall SHO
```bash
# Linux/macOS
./scripts/linux-installer.sh --operation=uninstall

# Windows
.\scripts\windows-installer.ps1 --operation=uninstall --env=prod
```

### Getting Started

Once installation is complete:

1. Access the SHO console via the provided URL (typically `http://<load-balancer-ip>:5050`)
2. Log in to your OutSystems tenant
3. Navigate to the Self-Hosted Setup section
4. Follow the tenant-specific configuration instructions
5. Begin deploying applications to your self-hosted environment

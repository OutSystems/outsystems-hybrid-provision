# outsystems-hybrid-provision
Self hosted version of ODC


## Table of Contents
1. [Overview](#overview)
2. [Keyfeatures](#keyfeatures)
3. [Usage](#usage)
4. [Installation](#installation)


## Overview

The Outsystems-hybrid-provision hosts the installation setup for the self-hosted version of outsystems ODC product.

Outsystems-hybrid-provision product is a low-code application development platform that enables your applications and data to host on your infrastructure (private cloud or on-premises). This Hybrid Low-Code Platform, a next-generation application development platform designed for enterprises that need the speed of low-code development with the control of on-premises data management.

Unlike fully cloud-hosted platforms, this solution offers the flexibility to run critical workloads on your infrastructure, while seamlessly integrating with cloud-based services for centralized control, updates, and monitoring.

It supports both Openshift and Kubernetes. However, the build and deploy of the applications will still remain with Outsystems ODC. ODC Portal and ODC Studio work together, making it quick to get the tools you need to develop and deploy your apps.

Before you can use ODC Studio, download it from the ODC Portal and login to your Outsystems tenant.


## Keyfeatures

    Hybrid Deployment Model

        Core services deployed in the customer's environment (on-prem or private cloud)

    Customer-Owned Data

        All application and user data is stored and processed within the customer's controlled environment

    Low-Code Development Experience

        Drag-and-drop visual builder

        Pre-built templates and integrations

        Reusable components and custom code support


For the setup of the self-hosted operator, the cluster must meet the following requirements:

1. At least 3 worker nodes
2. Minimum of 4 CPU Cores per worker node
3. Minimum of 4 GB RAM per worker node
4. OpenShift version >= 4.15.9* or Kubernetes* >= 1.28
5. Internet connectivity (or whitelist Outsystems domains)


## Usage

Before the installation of the setup, login to the web tenant and select the Self-Hosted Setup command based on the operating system. The command verifies and setup helm, kubectl, self-hosted operator. The command also checks and setups the load balancer for exposing the self-hosted operator service.

The setup also serves the uninstallation of the product.


## Installation


Before proceeding with the setup of self-hosted ODC product, generate the credentials from the tenant URL to login, access the self-hosted setup and select the OS from where the product is initialized.


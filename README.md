---
services: aks, cli
author: paolosalvatori
---

# Introduction #
These two bash scripts fully automate all the steps necessary to to build an Azure Kubernetes Service (AKS) cluster on Azure configured to use Azure Active Directory (AD) for user authentication, as explained at [Integrate Azure Active Directory with Azure Kubernetes Service](https://docs.microsoft.com/en-us/azure/aks/aad-integration).

- **create-aks-cluster-same-tenant**: this script uses the same Azure Active Directory tenant of the Azure subscription for user authentication.
- **create-aks-cluster-different-tenant**: this script uses a separate Azure Active Directory tenant for user authentication other than the tenant used by the Azure subscription.

# Description #
The variables in the first part of the two scripts contain the information necessary to build the AKS cluster:

- display name, user principal name and password to create or select an existing admin user from the Azure AD tenant used by the AKS cluster for user authentication
- name and resource group name of the Log Analytics workspace used to monitor the AKS cluster. This data is optional.
- name, resource group name and location of the Azure Kubernetes Service (AKS) cluster. The name of the cluster is also used to create or select an existing admin group in the Azure AD tenant.
- name and tenantId of the Azure Active Directory tenant used by the AKS cluster for user authentication. In the script, the Azure AD tenant used by the AKS cluster for user authentication, differs from the tenantId of the subscription. You can easily modify the script to use the same tenantId for both the subscription and user authentication.
- service principal, server application and client application used by the AKS cluster
- end date and years for registered applications and service principals
- password for the AKS service principal (optional)

Scripts contain comments and individual steps are fully descriptive.  
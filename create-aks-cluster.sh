#!/bin/bash

# variables

# data necessary to identify or create an admin user in the admin users group
userPrincipalName="han.solo@babo.onmicrosoft.com" # user principal name
userDisplayName="Han Solo" # user display name
userPassword="Whatever1!" # user password. This field is used only when creating a new user

# name and resource group name of the Log Analytics workspace used to monitor the AKS cluster. This data is optional.
logAnalyticsName="BaboAksCluster"
logAnalyticsResourceGroup="BaboAksLogAnalyticsResourceGroup"

# name, resource group name and location of the Azure Kubernetes Service (AKS) cluster
aksName="BaboAks"
aksResourceGroup="BaboAksResourceGroup"
location="WestEurope"

# node count, node size, and ssh key location for AKS nodes
nodeCount=5
nodeSize="Standard_DS5_v2"
sshKeyValue="/mnt/c/Users/hansolo/.ssh/id_rsa.pub"

# name and resource group name of the Azure Container Registry used by the AKS cluster. 
# The name of the cluster is also used to create or select an existing admin group in the Azure AD tenant.
acrName="HanSolo"
acrResourceGroup="ContainerRegistryResourceGroup"

# name and tenantId of the Azure Active Directory tenant used by the AKS cluster for user authentication.
# In the script, the Azure AD tenant used by the AKS cluster for user authentication, differs from the tenantId of the subscription.
# ou can easily modify the script to use the same tenantId for both the subscription and user authentication.
aksTenantName="babo"
aksTenantId="769ea97c-d6f6-48f3-a452-7d6ef2e3c8cb"

# service principal, server application and client application used by the AKS cluster
aksServicePrincipal="BaboAksServicePrincipal"
aksServerApplication="BaboAksServerApplication"
aksClientApplication="BaboAksClientApplication"

# end date and years for registered applications and service principals
endDate="2050-12-31"
years=50

# password for the AKS service principal
password="h0neym00n"

# subscriptionId and tenantId of the current subscription
subscriptionId=$(az account show --query id --output tsv)
tenantId=$(az account show --query tenantId --output tsv)

# login to the Azure AD tenant used for users
currentTenantId=$(az login --tenant $aksTenantId --allow-no-subscriptions --query [0].tenantId --output tsv 2> /dev/null)

if [[ -n $currentTenantId ]] && [[ $currentTenantId == $aksTenantId ]]; then
    echo "Successfully logged in ["$aksTenantId"] tenant"
else
    echo "Failed to login to ["$aksTenantId"] tenant"
    exit
fi

# Retrieve the objectId of the user in the Azure AD tenant used by AKS for user authentication 
echo "Retrieving the objectId of the ["$userPrincipalName"] user..."
userObjectId=$(az ad user show --upn-or-object-id $userPrincipalName --query objectId --output tsv 2> /dev/null)

if [[ -n userObjectId ]]; then
    echo "["$userPrincipalName"] user already exists in ["$aksTenantId"] tenant with ["$userObjectId"] objectId"
else
    echo "Failed to retrieve the objectId of the ["$userPrincipalName"] user"
    echo "Creating ["$userPrincipalName"] group in ["$aksTenantId"] tenant..."

    # create user in Azure AD
    userObjectId=$(az ad user create \
    --display-name $userDisplayName \
    --password $userPassword \
    --user-principal-name $userPrincipalName \
    --query objectId \
    --output tsv)

    if [[ $? == 0 ]]; then
        echo "["$userPrincipalName"] user successfully created in ["$aksTenantId"] tenant with [$userObjectId] objectId"
    else
        echo "Failed to create ["$userPrincipalName"] user in ["$aksTenantId"] tenant"
        exit
    fi
fi

# check it the AKS admins group already exists in the Azure AD tenant
aksAdminsGroup=$aksName"Admins"
echo "Checking if ["$aksAdminsGroup"] group actually exists in ["$aksTenantId"] tenant..."

groupObjectId=$(az ad group show --group $aksAdminsGroup --query objectId --output tsv 2> /dev/null)

if [[ -n $groupObjectId ]]; then
    echo "["$aksAdminsGroup"] group already exists in ["$aksTenantId"] tenant with ["$groupObjectId"] objectId"
else
    echo "No ["$aksAdminsGroup"] group actually exists in ["$aksTenantId"] tenant"
    echo "Creating ["$aksAdminsGroup"] group in ["$aksTenantId"] tenant..."

    # create mail nickname for the admins group
    email=${aksAdminsGroup,,}

    # create admins group in Azure AD
    groupObjectId=$(az ad group create \
    --display-name $aksAdminsGroup \
    --mail-nickname $email \
    --query objectId \
    --output tsv)

    if [[ $? == 0 ]]; then
        echo "["$aksAdminsGroup"] group successfully created in ["$aksTenantId"] tenant with [$groupObjectId] objectId"
    else
        echo "Failed to create ["$aksAdminsGroup"] group in ["$aksTenantId"] tenant"
        exit
    fi
fi

# check if the user is already a member of the admins group
isMember=$(az ad group member check --group $groupObjectId --member-id $userObjectId --query value --output tsv)

if [[ $isMember == "true" ]]; then
    echo "["$userPrincipalName"] user is already a member of ["$aksAdminsGroup"] group in ["$aksTenantId"] tenant"
else
    # adding user the admins group
    echo "Adding ["$userPrincipalName"] user as a member to ["$aksAdminsGroup"] group in ["$aksTenantId"] tenant..."
    az ad group member add \
    --group $groupObjectId \
    --member-id $userObjectId &> /dev/null

    if [[ $? == 0 ]]; then
        echo "["$userPrincipalName"] user successfully added as a member to ["$aksAdminsGroup"] group in ["$aksTenantId"] tenant"
    else
        echo "Failed to add ["$userPrincipalName"] user as a member to ["$aksAdminsGroup"] group in ["$aksTenantId"] tenant"
        exit
    fi
fi

# check if the server application already exists
echo "Checking if ["$aksServerApplication"] server application actually exists in ["$aksTenantId"] tenant..."

aksServerApplicationId="http://"$aksServerApplication"."$aksTenantName".onmicrosoft.com"

az ad app show --id $aksServerApplicationId &> /dev/null

if [[ $? != 0 ]]; then
	echo "No ["$aksServerApplication"] server application actually exists in ["$aksTenantId"] tenant"
    echo "Creating ["$aksServerApplication"] server application in ["$aksTenantId"] tenant..."

    # create the server application
    #--required-resource-accesses k8s-api-permissions-manifest.json \
    aksServerApplicationAppId=$(az ad app create \
    --display-name $aksServerApplication \
    --identifier-uris $aksServerApplicationId \
    --key-type Password \
    --password $password \
    --available-to-other-tenants true \
    --reply-urls $aksServerApplicationId \
    --end-date $endDate \
    --native-app false \
    --query appId \
    --output tsv)

    if [[ $? == 0 ]]; then
        echo "["$aksServerApplication"] server application successfully created in ["$aksTenantId"] tenant with [$aksServerApplicationAppId] appId"
    else
        echo "Failed to create ["$aksServerApplication"] server application in ["$aksTenantId"] tenant"
        exit
    fi

    echo "Assigning service principal to ["$aksServerApplication"] server application..."
    az ad sp create --id $aksServerApplicationAppId 1> /dev/null

    if [[ $? == 0 ]]; then
        echo "Service principal successfully assigned to [$aksServerApplication] server application"
    else
        echo "Failed to assign service principal to ["$aksServerApplication"] server application"
        exit
    fi

    # set the groupMembershipClaims value to "All"
    az ad app update \
    --id $aksServerApplicationId \
    --set groupMembershipClaims=All 1> /dev/null

    if [[ $? == 0 ]]; then
        echo "Successfully set groupMembershipClaims value to All for the ["$aksServerApplication"] server application"
    else
        echo "Failed to set groupMembershipClaims value to All for the ["$aksServerApplication"] server application"
        exit
    fi

    # add application permissions \ roles
    az ad app permission add \
    --id $aksServerApplicationAppId \
    --api 00000003-0000-0000-c000-000000000000 \
    --api-permissions 7ab1d382-f21e-4acd-a863-ba3e13f7da61=Role \
                      06da0dbc-49e2-44d2-8312-53f166ab848a=Scope \
                      e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope

    az ad app permission add \
    --id $aksServerApplicationAppId \
    --api 00000002-0000-0000-c000-000000000000 \
    --api-permissions 311a71cc-e848-46a1-bdf8-97ff7156d8e6=Scope

    if [[ $? == 0 ]]; then
        echo "Application and delegated permissions successfully added to the ["$aksServerApplication"] server application"
    else
        echo "Failed to add application and delegated permissions to the ["$aksServerApplication"] server application"
        exit
    fi

    # grant application permissions \ roles
    az ad app permission admin-consent --id $aksServerApplicationAppId

    if [[ $? == 0 ]]; then
        echo "Admin consent successfully granted to the ["$aksServerApplication"] server application"
    else
        echo "Failed to grant admin consent to the ["$aksServerApplication"] server application"
        exit
    fi
else
	echo "["$aksServerApplication"] server application already exists in ["$aksTenantId"] tenant"
    echo "Retrieving appId for ["$aksServerApplication"] server application..."
    aksServerApplicationAppId=$(az ad app show --id $aksServerApplicationId --query appId --output tsv)

    if [[ -n $aksServerApplicationAppId ]]; then
        echo "Successfully retrieved ["$aksServerApplicationAppId"] appdId for the ["$aksServerApplication"] server application"
    else
        echo "Failed to retrieve the appId for the ["$aksServerApplication"] server application"
        exit
    fi
fi

# check if the client application already exists
echo "Checking if ["$aksClientApplication"] client application actually exists in ["$aksTenantId"] tenant..."

aksClientApplicationId=$aksClientApplication"."$aksTenantName".onmicrosoft.com"

aksClientApplicationAppId=$(az ad app list --query "[?displayName=='$aksClientApplication'].appId" --output tsv)
if [[ -z $aksClientApplicationAppId ]]; then
	echo "No ["$aksClientApplication"] client application actually exists in ["$aksTenantId"] tenant"
    echo "Creating ["$aksClientApplication"] client application in ["$aksTenantId"] tenant..."

    # create the client application
    aksClientApplicationAppId=$(az ad app create \
    --native-app true \
    --display-name $aksClientApplication \
    --key-type Password \
    --password $password \
    --available-to-other-tenants true \
    --reply-urls $aksClientApplicationId \
    --homepage $aksClientApplicationId \
    --end-date $endDate \
    --native-app true \
    --query appId \
    --output tsv)

    if [[ $? == 0 ]]; then
        echo "["$aksClientApplication"] client application successfully created in ["$aksTenantId"] tenant with [$aksClientApplicationAppId] appId"
    else
        echo "Failed to create ["$aksClientApplication"] client application in ["$aksTenantId"] tenant"
        exit
    fi

    # get the id of the access delegated permission to the server application
    accessPermissionId=$(az ad app show --id $aksServerApplicationId --query oauth2Permissions[0].id --output tsv)

    if [[ -n $accessPermissionId ]]; then
        echo "["$accessPermissionId"] id of the [Access "$aksServerApplication"] delegated permission successfully retrieved"
    else
        echo "Failed to retrieve the id of the [Access "$aksServerApplication"] delegated permission" 
        exit
    fi

    # add to the client application the delegated permission to access the server application
    az ad app permission add \
    --id $aksClientApplicationAppId \
    --api $aksServerApplicationAppId \
    --api-permissions $accessPermissionId=Scope

    az ad app permission add \
    --id $aksClientApplicationAppId \
    --api 00000002-0000-0000-c000-000000000000 \
    --api-permissions 311a71cc-e848-46a1-bdf8-97ff7156d8e6=Scope 

    if [[ $? == 0 ]]; then
        echo "[Access "$aksServerApplication"] delegated permission successfully added to the ["$aksClientApplication"] client application"
    else
        echo "Failed to add the [Access "$aksServerApplication"] delegated permission to the ["$aksClientApplication"] client application"
        exit
    fi

    # grant application permissions \ roles
    az ad app permission admin-consent --id $aksClientApplicationAppId

    if [[ $? == 0 ]]; then
        echo "Admin consent successfully granted to the ["$aksClientApplication"] server application"
    else
        echo "Failed to grant admin consent to the ["$aksClientApplication"] server application"
        exit
    fi
else
	echo "["$aksClientApplication"] client application already exists in ["$aksTenantId"] tenant with [$aksClientApplicationAppId] appId"
fi

# login to the Azure AD tenant used for users
currentTenantId=$(az login --subscription $subscriptionId --query [0].tenantId --output tsv 2> /dev/null)

if [[ -n $currentTenantId ]] && [[ $currentTenantId == $tenantId ]]; then
    echo "Successfully logged in ["$tenantId"] tenant"
else
    echo "Failed to login to ["$tenantId"] tenant"
    exit
fi

# get the last Kubernetes version available in the region
kubernetesVersion=$(az aks get-versions --location $location --query orchestrators[-1].orchestratorVersion --output tsv)

if [[ -n $kubernetesVersion ]]; then
    echo "Successfully retrieved the last Kubernetes version ["$kubernetesVersion"] supported by AKS in ["$location"] Azure region"
else
    echo "Failed to retrieve the last Kubernetes version supported by AKS in ["$location"] Azure region"
    exit
fi

# check the format of the service principal
if [[ $aksServicePrincipal != http://* ]]; then
    aksServicePrincipal="http://"$aksServicePrincipal
fi

# check if the service principal already exists
echo "Checking if ["$aksServicePrincipal"] service principal actually exists in ["$tenantId"] tenant..."

az ad sp show --id $aksServicePrincipal &> /dev/null

if [[ $? != 0 ]]; then
	echo "No ["$aksServicePrincipal"] service principal actually exists in ["$tenantId"] tenant"
    echo "Creating ["$aksServicePrincipal"] service principal in ["$tenantId"] tenant..."

     # create the service principal
        az ad sp create-for-rbac \
        --name $aksServicePrincipal \
        --password $password \
        --skip-assignment \
        --years $years 1> /dev/null

    if [[ $? == 0 ]]; then
        aksServicePrincipalAppId=$(az ad sp show --id $aksServicePrincipal --query appId --output tsv)
        echo "["$aksServicePrincipal"] service principal successfully created in ["$tenantId"] tenant with appId=["$aksServicePrincipalAppId"]"
    else
        echo "Failed to create ["$aksServicePrincipal"] service principal in ["$tenantId"] tenant"
        exit
    fi
else
    aksServicePrincipalAppId=$(az ad sp show --id $aksServicePrincipal --query appId --output tsv)
	echo "["$aksServicePrincipal"] service principal already exists in ["$tenantId"] tenant with appId=["$aksServicePrincipalAppId"]"
fi


# check if the resource group already exists
echo "Checking if ["$aksResourceGroup"] resource group actually exists in the ["$subscriptionId"] subscription..."

az group show --name $aksResourceGroup &> /dev/null

if [[ $? != 0 ]]; then
	echo "No ["$aksResourceGroup"] resource group actually exists in the ["$subscriptionId"] subscription"
    echo "Creating ["$aksResourceGroup"] resource group in the ["$subscriptionId"] subscription..."
    
    # create the resource group
    az group create --name $aksResourceGroup --location $location 1> /dev/null
        
    if [[ $? == 0 ]]; then
        echo "["$aksResourceGroup"] resource group successfully created in the ["$subscriptionId"] subscription"
    else
        echo "Failed to create ["$aksResourceGroup"] resource group in the ["$subscriptionId"] subscription"
        exit
    fi
else
	echo "["$aksResourceGroup"] resource group already exists in the ["$subscriptionId"] subscription"
fi

# retrieve resource id for the azure container registry
echo "Retrieving the resource id of the ["$acrName"] azure container registry..."
acrResourceId=$(az acr show --name $acrName --resource-group $acrResourceGroup --query id --output tsv 2> /dev/null)

if [[ -n $acrResourceId ]]; then
    echo "Resource id for the ["$acrName"] azure container registry successfully retrieved: ["$acrResourceId"]"
else
    echo "Failed to retrieve resource id of the ["$acrName"] azure container registry"
    return
fi

# to access images stored in ACR, you must grant the AKS service principal the correct rights to pull images from ACR
echo "Checking if ["$aksServicePrincipal"] service principal has been assigned to Reader, Contributor, or Owner role  for the ["$acrName"] azure container registry..."
role=$(az role assignment list --assignee $aksServicePrincipalAppId --scope $acrResourceId --query [?roleDefinitionName].roleDefinitionName --output tsv 2> /dev/null)

if [[ $role == "Owner" ]] || [[ $role == "Contributor" ]] || [[ $role == "Reader" ]]; then
    echo "["$aksServicePrincipal"] service principal is already assigned to the ["$role"] role for the ["$acrName"] azure container registry"
else
    echo "["$aksServicePrincipal"] service principal is not assigned to the Reader, Contributor, or Owner role for the ["$acrName"] azure container registry"
    echo "Assigning the ["$aksServicePrincipal"] service principal to the Reader role for the ["$acrName"] azure container registry..."

    az role assignment create \
    --assignee $aksServicePrincipalAppId \
    --role Reader \
    --scope $acrResourceId 1> /dev/null

    if [[ $? == 0 ]]; then
        echo "["$aksServicePrincipal"] service principal successfully assigned to the [Reader] role of the ["$acrName"] azure container registry"
    else
        echo "Failed to assign the ["$aksServicePrincipal"] service principal to the [Reader] role of the ["$acrName"] azure container registry"
        exit
    fi
fi

# check if log analytics workspace exists and retrieve its resource id
echo "Retrieving ["$logAnalyticsName"] Log Analytics resource id..."
workspaceResourceId=$(az resource show \
    --name $logAnalyticsName \
    --resource-group $logAnalyticsResourceGroup \
    --resource-type microsoft.operationalinsights/workspaces \
    --query id \
    --output tsv 2> /dev/null)

if [[ -n $workspaceResourceId ]]; then
    echo "Successfully retrieved the resource id for the ["$logAnalyticsName"] log analytics workspace"
else
    echo "Failed to retrieve the resource id for the ["$logAnalyticsName"] log analytics workspace"
fi

# create AKS cluster
echo "Checking if ["$aksName"] aks cluster actually exists in the ["$aksResourceGroup"] resource group..."

az aks show --name $aksName --resource-group $aksResourceGroup &> /dev/null

if [[ $? != 0 ]]; then
	echo "No ["$aksName"] aks cluster actually exists in the ["$aksResourceGroup"] resource group"
    echo "Creating ["$aksName"] aks cluster in the ["$aksResourceGroup"] resource group..."

    # Create the aks cluster
    if [[ -n $workspaceResourceId ]]; then
        az aks create \
        --name $aksName \
        --resource-group $aksResourceGroup \
        --location $location \
        --kubernetes-version $kubernetesVersion \
        --ssh-key-value $sshKeyValue \
        --node-vm-size $nodeSize \
        --node-count $nodeCount \
        --service-principal $aksServicePrincipalAppId \
        --client-secret $password \
        --enable-addons monitoring,http_application_routing \
        --aad-server-app-id $aksServerApplicationAppId \
        --aad-server-app-secret $password \
        --aad-client-app-id $aksClientApplicationAppId \
        --aad-tenant-id $aksTenantId \
        --workspace-resource-id $workspaceResourceId 1> /dev/null
    else
        az aks create \
        --name $aksName \
        --resource-group $aksResourceGroup \
        --location $location \
        --kubernetes-version $kubernetesVersion \
        --ssh-key-value $sshKeyValue \
        --node-vm-size $nodeSize \
        --node-count $nodeCount \
        --service-principal $aksServicePrincipalAppId \
        --client-secret $password \
        --enable-addons http_application_routing \
        --aad-server-app-id $aksServerApplicationAppId \
        --aad-server-app-secret $password \
        --aad-client-app-id $aksClientApplicationAppId \
        --aad-tenant-id $aksTenantId 1> /dev/null
    fi

    if [[ $? == 0 ]]; then
        echo "["$aksName"] aks cluster successfully created in the ["$aksResourceGroup"] resource group"
    else
        echo "Failed to create ["$aksName"] aks cluster in the ["$aksResourceGroup"] resource group"
        exit
    fi
else
	echo "["$aksName"] aks cluster already exists in the ["$aksResourceGroup"] resource group"
fi

# Install Kubernetes CLI (kubectl)
echo "Installing  Kubernetes CLI..."
az aks install-cli &> /dev/null

if [[ $? == 0 ]]; then
    echo "Kubernetes CLI successfully installed"
else
    echo "Failed to install Kubernetes CLI"
    exit
fi

# Check if an admin context with the same name already exist in kubectl configuration and if yes, remove it
kubectl config get-contexts $aksName"-admin" -o name &> /dev/null

if [[ $? == 0 ]]; then
    echo "A cluster called ["$aksName"] already exists in kubectl configuration"

    clusterAdmin="clusterAdmin_"$aksResourceGroup"_"$aksName
    echo "Removing ["$clusterAdmin"] user from kubectl configuration..."
    kubectl config unset "users."$clusterAdmin

    clusterUser="clusterUser_"$aksResourceGroup"_"$aksName
    echo "Removing ["$clusterUser"] user from kubectl configuration..."
    kubectl config unset "users."$clusterUser

    echo "Removing ["$aksName"] cluster from kubectl configuration..."
    kubectl config delete-cluster $aksName

    if [[ $? == 0 ]]; then
        echo "["$aksName"] cluster successfully removed from kubectl configuration"
    else
        echo "Failed to remove ["$aksName"] cluster from kubectl configuration"
        exit
    fi

    echo "Removing ["$aksName"] context from kubectl configuration..."
    kubectl config delete-context $aksName"-admin"

    if [[ $? == 0 ]]; then
        echo "["$aksName"] context successfully removed from kubectl configuration"
    else
        echo "Failed to remove ["$aksName"] context from kubectl configuration"
        exit
    fi
else
    echo "No cluster called ["$aksName"] actually exists in kubectl configuration"
fi

# Use the following command to configure kubectl to connect to the new Kubernetes cluster
echo "Getting access credentials configure kubectl to connect to the ["$aksName"] AKS cluster..."
az aks get-credentials --name $aksName --resource-group $aksResourceGroup --admin

if [[ $? == 0 ]]; then
    echo "Credentials for the ["$aksName"] cluster successfully retrieved"
else
    echo "Failed to retrieve the credentials for the ["$aksName"] cluster"
    exit
fi

if [[ -z $userObjectId ]]; then 
    exit
fi

echo "Creating admin cluster role binding for the ["$userPrincipalName"] user..."
# Use the following manifest to create a ClusterRoleBinding for the admins group in Azure AD
# This cluster role binding provides full access to all the namespaces in the cluster
# for more information on Kubernetes RBAC, see https://kubernetes.io/docs/reference/access-authn-authz/rbac/
echo "apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: "${aksName,,}"-cluster-admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: \"$groupObjectId\"" | kubectl apply -f -
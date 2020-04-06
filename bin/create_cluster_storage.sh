#!/usr/bin/env bash

set -ex

#####
# Create storage for Pangeo on Azure. This includes a number of elements:
#   * Check for existing storage accounts in the pangeo resource group
#   * Create an azure storage account to logically track all Pangeo storage on Azure, if it doesn't already exist
#   * Apply the `azurefile` Kubernetes storage class config
#   * Apply the azure PVC cluster role config
#####

# Get kubernetes credentials for AKS resource.
az aks get-credentials -g $RESOURCE_GROUP_NAME -n $CLUSTER_NAME --overwrite-existing
az provider register --namespace Microsoft.NetApp --wait # TODO: not sure if this is needed. Once, never, always...

# Create storage for homespaces if does't exist already.
# Using NetApp File
# Code mostly taken from https://docs.microsoft.com/bs-latn-ba/azure/aks/azure-netapp-files
CLUSTER_NODE_RESOURCE_GROUP=$(az aks show --resource-group $RESOURCE_GROUP_NAME --name $CLUSTER_NAME  --query nodeResourceGroup -o tsv)
STORAGE_POOL_NAME="kubernetes-storage"
SERVICE_LEVEL="Premium"
STORAGE_ACCOUNT_SIZE=4 #TiB
declare -a VOLUMES=("nfs")
declare -a VOLUME_SIZES=(4000) # GiB

# Storage account
if ! az netappfiles account show -n $STORAGE_ACCT_NAME --resource-group $CLUSTER_NODE_RESOURCE_GROUP >/dev/null 2>&1 ; then
    az netappfiles account create \
        --resource-group $CLUSTER_NODE_RESOURCE_GROUP \
        --location $RESOURCE_LOCATION \
        --account-name $STORAGE_ACCT_NAME
fi

# Storage pool
if ! az netappfiles pool show -n $STORAGE_POOL_NAME  --resource-group $CLUSTER_NODE_RESOURCE_GROUP --account-name $STORAGE_ACCT_NAME >/dev/null 2>&1 ; then
    az netappfiles pool create \
        --resource-group $CLUSTER_NODE_RESOURCE_GROUP \
        --location $RESOURCE_LOCATION \
        --account-name $STORAGE_ACCT_NAME \
        --pool-name $STORAGE_POOL_NAME \
        --size $STORAGE_ACCOUNT_SIZE \
        --service-level $SERVICE_LEVEL
fi

# Delegate a subnet. Create a subnet outside of the K8 subnet range but in the vnet range 
K8_RANGE=$(az network vnet subnet show --name $K8_SUB_NET_NAME --resource-group $RESOURCE_GROUP_NAME --vnet-name $V_NET_NAME --query "addressPrefix" -o tsv)
STORAGE_RANGE=$(echo "$K8_RANGE" | cut -d"/" -f 1 | cut -d"." -f 1,2)".88.0/24"
VNET_ID=$(az network vnet show --resource-group $RESOURCE_GROUP_NAME --name $V_NET_NAME --query "id" -o tsv)
if ! az network vnet subnet show --vnet-name $V_NET_NAME --resource-group $RESOURCE_GROUP_NAME --name  $STORAGE_SUB_NET_NAME >/dev/null 2>&1 ; then
    az network vnet subnet create \
        --resource-group $RESOURCE_GROUP_NAME \
        --vnet-name $V_NET_NAME \
        --name $STORAGE_SUB_NET_NAME \
        --delegations "Microsoft.NetApp/volumes" \
        --address-prefixes $STORAGE_RANGE
fi
SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP_NAME --vnet-name $V_NET_NAME --name $STORAGE_SUB_NET_NAME --query "id" -o tsv)


NUM_VOLS=${#VOLUMES[@]}
for (( i=0; i<${NUM_VOLS}; i++ ));
do
    echo "Storage for volume $i..."
    VOLUME_SIZE=${VOLUME_SIZES[$i]}
    VOLUME_NAME=${VOLUMES[$i]}
    UNIQUE_NAME=$(echo "$STORAGE_ACCT_NAME-$VOLUME_NAME" | tr -cd '[a-zA-Z0-9]' | cut -c1-70) # Please note that creation token needs to be unique within all ANF Accounts

    if ! az netappfiles volume show --resource-group $CLUSTER_NODE_RESOURCE_GROUP  --account-name $STORAGE_ACCT_NAME --pool-name $STORAGE_POOL_NAME  --volume-name $UNIQUE_NAME  >/dev/null 2>&1 ; then
        az netappfiles volume create \
            --resource-group $CLUSTER_NODE_RESOURCE_GROUP \
            --location $RESOURCE_LOCATION \
            --account-name $STORAGE_ACCT_NAME \
            --pool-name $STORAGE_POOL_NAME \
            --name $UNIQUE_NAME \
            --service-level $SERVICE_LEVEL \
            --vnet $VNET_ID \
            --subnet $SUBNET_ID \
            --usage-threshold $VOLUME_SIZE \
            --file-path $UNIQUE_NAME \
            --protocol-types "NFSv3"
    fi
    
    if ! kubectl get pv pv-${VOLUME_NAME}  >/dev/null 2>&1 ; then

        IP=$(az netappfiles volume show --resource-group $CLUSTER_NODE_RESOURCE_GROUP --account-name $STORAGE_ACCT_NAME --pool-name $STORAGE_POOL_NAME --volume-name $UNIQUE_NAME --query "mountTargets[0].ipAddress" -o tsv)
        VOLUME_PATH=$(az netappfiles volume show --resource-group $CLUSTER_NODE_RESOURCE_GROUP --account-name $STORAGE_ACCT_NAME --pool-name $STORAGE_POOL_NAME --volume-name $UNIQUE_NAME --query "creationToken" -o tsv)

        cat  ../charts/netapp-files-pv.template.yaml | \
            sed "s/[$][{]VOLUME_NAME[}]/$VOLUME_NAME/g" | \
            sed "s/[$][{]VOLUME_SIZE[}]/$VOLUME_SIZE/g" | \
            sed "s/[$][{]IP[}]/$IP/g" | \
            sed "s/[$][{]VOLUME_PATH[}]/$VOLUME_PATH/g" | \
            kubectl apply -f  - 
    fi
done

# Create storage account for blobs
if !  az storage account show --name $BLOB_STORAGE_ACCT_NAME >/dev/null 2>&1 ; then
    az storage account create --name $BLOB_STORAGE_ACCT_NAME \
                              --resource-group $RESOURCE_GROUP_NAME \
                              --location $RESOURCE_LOCATION
fi

# Add blob storage flex volume
kubectl apply -f https://raw.githubusercontent.com/Azure/kubernetes-volume-drivers/master/flexvolume/blobfuse/deployment/blobfuse-flexvol-installer-1.9.yaml

# BLOB_FUSE_SECRET_NAME="blobfusecreds"
# BLOB_STORAGE_ACCT_KEY=$(az storage account keys list --account-name $BLOB_STORAGE_ACCT_NAME --query "[?permissions == 'Full'] | [0].value" --output tsv)
# if kubectl -n default get secret $BLOB_FUSE_SECRET_NAME >/dev/null 2>&1  ; then
#     kubectl -n default delete secret $BLOB_FUSE_SECRET_NAME
# fi
# kubectl create secret generic $BLOB_FUSE_SECRET_NAME -n default --from-literal accountname=$BLOB_STORAGE_ACCT_NAME --from-literal accountkey=$BLOB_STORAGE_ACCT_KEY --type="azure/blobfuse"

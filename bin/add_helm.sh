#!/usr/bin/env bash

set -ex

#####
# Update an existing autoscaling Azure Kubernetes Service resource with helm and tiller,
# and specific helm charts.
#####

# Get kubernetes credentials for AKS resource.
az aks get-credentials -g $RESOURCE_GROUP_NAME -n $CLUSTER_NAME --overwrite-existing

# # Install dashboard
# if kubectl get ClusterRoleBinding kubernetes-dashboard  >/dev/null 2>&1 ; then 
#     # The install creates this so delete the existing one if exists.
#     kubectl delete ClusterRoleBinding kubernetes-dashboard
# fi
# kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0/aio/deploy/recommended.yaml


# Install and update helm and tiller.
kubectl apply -f ../charts/helm_rbac.yaml
helm init --upgrade --service-account tiller --wait

# Install helm charts to customise the cluster.
helm upgrade --install --namespace kube-system external-dns stable/external-dns \
             -f ../charts/external_dns_config.yaml \
             -f ../charts/azure-secrets.yaml
helm upgrade --install --namespace kube-system nginx-ingress stable/nginx-ingress \
             -f ../charts/nginx-ingress-config.yaml

################
# Cert Manager #
################


kubectl create namespace cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install \
  --name cert-manager \
  --namespace cert-manager \
  --version v0.16.0 \
  jetstack/cert-manager \
  --set installCRDs=true \
   -f ../charts/cert-manager-config.yaml

# # Apply the cluster issuer.
kubectl apply -f ../charts/cluster-issuer.yaml

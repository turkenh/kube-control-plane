#!/usr/bin/env bash
set -euo pipefail

scriptdir="$( dirname "${BASH_SOURCE[0]}")"
kind_context=demo

if [[ -z "${KUBECONFIG:-}" ]]; then
  export KUBECONFIG="$HOME/.kube/config"
fi

echo "checking if kind cluster \"${kind_context}\" exists"

kind get kubeconfig --name ${kind_context} > /dev/null 2>&1 ||
{ echo "creating kind cluster"; kind version; kind create cluster --name="${kind_context}" --config=${scriptdir}/kind.yaml --kubeconfig="${KUBECONFIG}"; }

docker pull quay.io/jetstack/cert-manager-controller:v0.15.1
docker pull quay.io/jetstack/cert-manager-webhook:v0.15.1
docker pull gcr.io/etcd-development/etcd:v3.3.22

kind load docker-image --name ${kind_context} quay.io/jetstack/cert-manager-controller:v0.15.1
kind load docker-image --name ${kind_context} quay.io/jetstack/cert-manager-webhook:v0.15.1
kind load docker-image --name ${kind_context} gcr.io/etcd-development/etcd:v3.3.22

kubectl create ns cert-manager -o yaml --dry-run | kubectl apply -f -
helm upgrade --install cert-manager jetstack/cert-manager --version v0.15.1 -n cert-manager --set installCRDs=true --set clusterResourceNamespace=etcd-system --wait

echo "wait until cert manager is ready..."
timeout=120
while :
do
  if kubectl apply -f "test-resources.yaml" >/dev/null 2>&1; then
    kubectl delete -f "test-resources.yaml" --wait=false >/dev/null 2>&1
    echo "wait until cert manager is ready... OK"
    break
  fi
  sleep 1
  if [[ "$timeout" -lt 0 ]]; then
    echo "time out while waiting for cert manager"
    exit 1
  fi
  ((timeout=timeout-1))
done

kubectl create ns etcd-system -o yaml --dry-run | kubectl apply -f -
helm upgrade --install etcd host-setup -n etcd-system --wait
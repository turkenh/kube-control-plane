#!/usr/bin/env bash
set -euo pipefail
scriptdir="$( dirname "${BASH_SOURCE[0]}")"

if [[ -z "${1:-}" ]]; then
  echo "Missing tenant id"
  exit 1
fi

tenant_id=$1
tenant_name="kube-tenant-${tenant_id}"

function k {
	kubectl -n ${tenant_name} "$@"
}

function kubeconfig_from_client_cert {
  client_secret_name=$1
  kubeconfig_secret_name=$2

  k wait cert $client_secret_name --for=condition=ready

  ca_cert=$(k get secret "${client_secret_name}" -o jsonpath='{ .data.ca\.crt }')
  client_cert=$(k get secret "${client_secret_name}" -o jsonpath='{ .data.tls\.crt }')
  client_key=$(k get secret "${client_secret_name}" -o jsonpath='{ .data.tls\.key }')

  if [ -z "${ca_cert}" ]; then echo "Missing ca cert"; exit 1; fi
  if [ -z "${client_cert}" ]; then echo "Missing client cert"; exit 1; fi
  if [ -z "${client_key}" ]; then echo "Missing client key"; exit 1; fi

kubeconfig=$(cat <<EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${ca_cert}
    server: https://tenant-kubernetes:6443
  name: tenant-kubernetes
contexts:
- context:
    cluster: tenant-kubernetes
    user: tenant-user
  name: tenant-user@tenant-kubernetes
current-context: tenant-user@tenant-kubernetes
kind: Config
preferences: {}
users:
- name: tenant-user
  user:
    client-certificate-data: ${client_cert}
    client-key-data: ${client_key}
EOF
)

  k delete secret "${kubeconfig_secret_name}" --ignore-not-found
  k create secret generic "${kubeconfig_secret_name}" --from-literal kubeconfig="${kubeconfig}"
}


###
kubectl create ns "${tenant_name}" -o yaml --dry-run | kubectl apply -f -
helm upgrade --install "${tenant_name}" kube-tenant -n "${tenant_name}" --set tenantID="${tenant_id}"
helm upgrade --install kubedebug https://storage.googleapis.com/helm-repo-dev/kubedebug-0.1.0.tgz -n "${tenant_name}"

kubeconfig_from_client_cert client-kube-controller-manager kube-controller-manager
kubeconfig_from_client_cert client-kubernetes-admin kubernetes-admin
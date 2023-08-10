set -euo pipefail xtrace

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

kubectl create ns prometheus || true
kubectl label ns prometheus scrape=enabled --overwrite=true

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    -n prometheus \
    -f ./.github/actions/e2e/install-prometheus/values.yaml \
    --set prometheus.prometheusSpec.remoteWrite[0].url=https://aps-workspaces.${AWS_DEFAULT_REGION}.amazonaws.com/workspaces/${WORKSPACE_ID}/api/v1/remote_write \
    --set prometheus.prometheusSpec.remoteWrite[0].sigv4.region=${AWS_DEFAULT_REGION} \
    --set prometheus.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::${AWS_ACCOUNT_ID}:role/prometheus-irsa-${CLUSTER_NAME}" \
    --set-string "kubelet.serviceMonitor.cAdvisorRelabelings[0].targetLabel=metrics_path" \
    --set-string "kubelet.serviceMonitor.cAdvisorRelabelings[0].action=replace" \
    --set-string "kubelet.serviceMonitor.cAdvisorRelabelings[0].sourceLabels[0]=__metrics_path__" \
    --set-string "kubelet.serviceMonitor.cAdvisorRelabelings[1].targetLabel=clusterName" \
    --set-string "kubelet.serviceMonitor.cAdvisorRelabelings[1].replacement=${CLUSTER_NAME}" \
    --set-string "kubelet.serviceMonitor.cAdvisorRelabelings[2].targetLabel=gitRef" \
    --set-string "kubelet.serviceMonitor.cAdvisorRelabelings[2].replacement=$(git rev-parse HEAD)" \
    --set-string "kubelet.serviceMonitor.cAdvisorRelabelings[3].targetLabel=mostRecentTag" \
    --set-string "kubelet.serviceMonitor.cAdvisorRelabelings[3].replacement=$(git describe --abbrev=0 --tags)" \
    --set-string "kubelet.serviceMonitor.cAdvisorRelabelings[4].targetLabel=commitsAfterTag" \
    --set-string "kubelet.serviceMonitor.cAdvisorRelabelings[4].replacement=$(git describe --tags | cut -d '-' -f 2)" \
    --wait

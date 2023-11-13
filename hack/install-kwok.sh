# get the latest version
KWOK_REPO=kubernetes-sigs/kwok
# KWOK_LATEST_RELEASE=$(curl "https://api.github.com/repos/${KWOK_REPO}/releases/latest" | jq -r '.tag_name')
KWOK_LATEST_RELEASE="v0.3.0"

# make a base directory for multi-base kustomization
HOME_DIR=$(mktemp -d)
BASE=${HOME_DIR}/base
mkdir ${BASE}
# allow it to tolerate everything, but not run on nodes that we launch
cat <<EOF > "${BASE}/tolerate-all.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kwok-controller
  namespace: kube-system
spec:
  template:
    spec:
      tolerations:
      - operator: "Exists"
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kwok.x-k8s.io/node
                operator: DoesNotExist
EOF

	cat <<EOF > "${BASE}/kustomization.yaml"
  apiVersion: kustomize.config.k8s.io/v1beta1
  kind: Kustomization
  images:
  - name: registry.k8s.io/kwok/kwok
    newTag: "${KWOK_LATEST_RELEASE}"
  resources:
  - "https://github.com/${KWOK_REPO}/kustomize/kwok?ref=${KWOK_LATEST_RELEASE}"
  patchesStrategicMerge:
  - tolerate-all.yaml
EOF

# Define 10 different kwok controllers to handle large load
for let in a b c d e f g h i j
do
  SUB_LET_DIR=$HOME_DIR/${let}
  mkdir ${SUB_LET_DIR}

  cat <<EOF > "${SUB_LET_DIR}/patch.yaml"
  - op: replace
    path: /spec/template/spec/containers/0/args/2
    value: --manage-nodes-with-label-selector=kwok-partition=${let}
EOF

	cat <<EOF > "${SUB_LET_DIR}/kustomization.yaml"
  apiVersion: kustomize.config.k8s.io/v1beta1
  kind: Kustomization
  images:
  - name: registry.k8s.io/kwok/kwok
    newTag: "${KWOK_LATEST_RELEASE}"
  resources:
  - ./../base
  nameSuffix: -${let}
  patches:
    - path: ${SUB_LET_DIR}/patch.yaml
      target:
        group: apps
        version: v1
        kind: Deployment
        name: kwok-controller
EOF

done

cat <<EOF > "${HOME_DIR}/kustomization.yaml"
resources:
- ./a
- ./b
- ./c
- ./d
- ./e
- ./f
- ./g
- ./h
- ./i
- ./j
EOF

kubectl kustomize "${HOME_DIR}" > "${HOME_DIR}/kwok.yaml"

kubectl apply -f ${HOME_DIR}/kwok.yaml

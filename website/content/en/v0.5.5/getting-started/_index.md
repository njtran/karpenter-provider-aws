
---
title: "Getting Started with Karpenter on AWS"
linkTitle: "Getting Started"
weight: 10
---

Karpenter automatically provisions new nodes in response to unschedulable
pods. Karpenter does this by observing events within the Kubernetes cluster,
and then sending commands to the underlying cloud provider.

In this example, the cluster is running on Amazon Web Services (AWS) Elastic
Kubernetes Service (EKS). Karpenter is designed to be cloud provider agnostic,
but currently only supports AWS. Contributions are welcomed.

This guide should take less than 1 hour to complete, and cost less than $0.25.
Follow the clean-up instructions to reduce any charges.

## Install

Karpenter is installed in clusters with a helm chart.

Karpenter additionally requires IAM Roles for Service Accounts (IRSA). IRSA
permits Karpenter (within the cluster) to make privileged requests to AWS (as
the cloud provider).

### Required Utilities

Install these tools before proceeding:

1. [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html)
2. `kubectl` - [the Kubernetes CLI](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
3. `eksctl` - [the CLI for AWS EKS](https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html)
4. `helm` - [the package manager for Kubernetes](https://helm.sh/docs/intro/install/)

Login to the AWS CLI with a user that has sufficient privileges to create a
cluster.

### Environment Variables

After setting up the tools, set the following environment variables to store
commonly used values.

```bash
export CLUSTER_NAME=$USER-karpenter-demo
export AWS_DEFAULT_REGION=us-west-2
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

### Create a Cluster

Create a cluster with `eksctl`. This example configuration file specifies a basic cluster with one initial node and sets up an IAM OIDC provider for the cluster to enable IAM roles for pods:

```bash
cat <<EOF > cluster.yaml
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_DEFAULT_REGION}
  version: "1.21"
  tags:
    karpenter.sh/discovery: ${CLUSTER_NAME}
managedNodeGroups:
  - instanceType: m5.large
    amiFamily: AmazonLinux2
    name: ${CLUSTER_NAME}-ng
    desiredCapacity: 1
    minSize: 1
    maxSize: 10
iam:
  withOIDC: true
EOF
eksctl create cluster -f cluster.yaml
```

This guide uses a managed node group to host Karpenter.

Karpenter itself can run anywhere, including on [self-managed node groups](https://docs.aws.amazon.com/eks/latest/userguide/worker.html), [managed node groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html), or [AWS Fargate](https://aws.amazon.com/fargate/).

Karpenter will provision EC2 instances in your account.

### Create the KarpenterNode IAM Role

Instances launched by Karpenter must run with an InstanceProfile that grants permissions necessary to run containers and configure networking. Karpenter discovers the InstanceProfile using the name `KarpenterNodeRole-${ClusterName}`.

First, create the IAM resources using AWS CloudFormation.

```bash
TEMPOUT=$(mktemp)

curl -fsSL https://karpenter.sh{{< relref "." >}}cloudformation.yaml  > $TEMPOUT \
&& aws cloudformation deploy \
  --stack-name Karpenter-${CLUSTER_NAME} \
  --template-file ${TEMPOUT} \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ClusterName=${CLUSTER_NAME}
```

Second, grant access to instances using the profile to connect to the cluster. This command adds the Karpenter node role to your aws-auth configmap, allowing nodes with this role to connect to the cluster.

```bash
eksctl create iamidentitymapping \
  --username system:node:{{EC2PrivateDNSName}} \
  --cluster  ${CLUSTER_NAME} \
  --arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME} \
  --group system:bootstrappers \
  --group system:nodes
```

Now, Karpenter can launch new EC2 instances and those instances can connect to your cluster.

### Create the KarpenterController IAM Role

Karpenter requires permissions like launching instances. This will create an AWS IAM Role, Kubernetes service account, and associate them using [IRSA](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/setting-up-enable-IAM.html).

```
eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME --name karpenter --namespace karpenter \
  --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/KarpenterControllerPolicy-$CLUSTER_NAME \
  --approve
```

### Create the EC2 Spot Service Linked Role

This step is only necessary if this is the first time you're using EC2 Spot in this account. More details are available [here](https://docs.aws.amazon.com/batch/latest/userguide/spot_fleet_IAM_role.html).
```bash
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com
# If the role has already been successfully created, you will see:
# An error occurred (InvalidInput) when calling the CreateServiceLinkedRole operation: Service role name AWSServiceRoleForEC2Spot has been taken in this account, please try a different suffix.
```

### Install Karpenter Helm Chart

Use helm to deploy Karpenter to the cluster.

We created a Kubernetes service account when we created the cluster using
eksctl. Thus, we don't need the helm chart to do that.

```bash
helm repo add karpenter https://charts.karpenter.sh
helm repo update
helm upgrade --install karpenter karpenter/karpenter --namespace karpenter \
  --create-namespace --set serviceAccount.create=false --version {{< param "latest_release_version" >}} \
  --set controller.clusterName=${CLUSTER_NAME} \
  --set controller.clusterEndpoint=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.endpoint" --output json) \
  --wait # for the defaulting webhook to install before creating a Provisioner
```

### Enable Debug Logging (optional)
```sh
kubectl patch configmap config-logging -n karpenter --patch '{"data":{"loglevel.controller":"debug"}}'
```

### Create Grafana dashboards (optional)

The Karpenter repo contains multiple [importable dashboards](https://github.com/aws/karpenter/tree/main/grafana-dashboards) for an existing Grafana instance. See the Grafana documentation for [instructions](https://grafana.com/docs/grafana/latest/dashboards/export-import/#import-dashboard) to import a dashboard.

#### Deploy a temporary Prometheus and Grafana stack (optional)

The following commands will deploy a Prometheus and Grafana stack that is suitable for this guide but does not include persistent storage or other configurations that would be necessary for monitoring a production deployment of Karpenter.

```sh
helm repo add grafana-charts https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

curl -fsSL https://karpenter.sh/docs/getting-started/prometheus-values.yaml | tee prometheus-values.yaml
helm install --namespace monitoring prometheus prometheus-community/prometheus --values prometheus-values.yaml

curl -fsSL https://karpenter.sh/docs/getting-started/grafana-values.yaml | tee grafana-values.yaml
helm install --namespace monitoring grafana grafana-charts/grafana --values grafana-values.yaml
```

The Grafana instance may be accessed using port forwarding.

```sh
kubectl port-forward --namespace monitoring svc/grafana 3000:80
```

The new stack has only one user, `admin`, and the password is stored in a secret. The following command will retrieve the password.

```sh
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode
```

### Provisioner

A single Karpenter provisioner is capable of handling many different pod
shapes. Karpenter makes scheduling and provisioning decisions based on pod
attributes such as labels and affinity. In other words, Karpenter eliminates
the need to manage many different node groups.

Create a default provisioner using the command below.
This provisioner uses `securityGroupSelector` and `subnetSelector` to discover resources used to launch nodes.
We applied the tag `karpenter.sh/discovery` in the `eksctl` command above.
Depending how these resources are shared between clusters, you may need to use different tagging schemes.

The `ttlSecondsAfterEmpty` value configures Karpenter to terminate empty nodes.
This behavior can be disabled by leaving the value undefined.

Review the [provisioner CRD](../provisioner) for more information. For example,
`ttlSecondsUntilExpired` configures Karpenter to terminate nodes when a maximum age is reached.

Note: This provisioner will create capacity as long as the sum of all created capacity is less than the specified limit.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot"]
  limits:
    resources:
      cpu: 1000
  provider:
    subnetSelector:
      karpenter.sh/discovery: ${CLUSTER_NAME}
    securityGroupSelector:
      karpenter.sh/discovery: ${CLUSTER_NAME}
    instanceProfile: KarpenterNodeInstanceProfile-${CLUSTER_NAME}
  ttlSecondsAfterEmpty: 30
EOF
```

## First Use

Karpenter is now active and ready to begin provisioning nodes.
Create some pods using a deployment, and watch Karpenter provision nodes in response.

### Automatic Node Provisioning

This deployment uses the [pause image](https://www.ianlewis.org/en/almighty-pause-container) and starts with zero replicas.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
spec:
  replicas: 0
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      terminationGracePeriodSeconds: 0
      containers:
        - name: inflate
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.2
          resources:
            requests:
              cpu: 1
EOF
kubectl scale deployment inflate --replicas 5
kubectl logs -f -n karpenter $(kubectl get pods -n karpenter -l karpenter=controller -o name)
```

### Automatic Node Termination

Now, delete the deployment. After 30 seconds (`ttlSecondsAfterEmpty`),
Karpenter should terminate the now empty nodes.

```bash
kubectl delete deployment inflate
kubectl logs -f -n karpenter $(kubectl get pods -n karpenter -l karpenter=controller -o name)
```

### Manual Node Termination

If you delete a node with kubectl, Karpenter will gracefully cordon, drain,
and shutdown the corresponding instance. Under the hood, Karpenter adds a
finalizer to the node object, which blocks deletion until all pods are
drained and the instance is terminated. Keep in mind, this only works for
nodes provisioned by Karpenter.

```bash
kubectl delete node $NODE_NAME
```

## Cleanup

To avoid additional charges, remove the demo infrastructure from your AWS account.

```bash
helm uninstall karpenter --namespace karpenter
eksctl delete iamserviceaccount --cluster ${CLUSTER_NAME} --name karpenter --namespace karpenter
aws cloudformation delete-stack --stack-name Karpenter-${CLUSTER_NAME}
aws ec2 describe-launch-templates \
    | jq -r ".LaunchTemplates[].LaunchTemplateName" \
    | grep -i Karpenter-${CLUSTER_NAME} \
    | xargs -I{} aws ec2 delete-launch-template --launch-template-name {}
eksctl delete cluster --name ${CLUSTER_NAME}
```

---

## Next Steps:

---
title: "Provisioning Configuration"
linkTitle: "Provisioning"
weight: 10
---

## spec.provider

This section covers parameters of the AWS Cloud Provider.

[Review these fields in the code.](https://github.com/awslabs/karpenter/blob/main/pkg/cloudprovider/aws/apis/v1alpha1/provider.go#L33)

### InstanceProfile
An `InstanceProfile` is a way to pass a single IAM role to an EC2 instance.

It is required, and specified by name. A suitable `KarpenterNodeRole` is created in the getting started guide.

```
spec:
  provider:
    instanceProfile: MyInstanceProfile
```

### LaunchTemplate

A launch template is a set of configuration values sufficient for launching an EC2 instance (e.g., AMI, storage spec).

A custom launch template is specified by name. If none is specified, Karpenter will automatically create a launch template.

Review the [Launch Template documentation](../launch-templates/) to learn how to create a custom one.

```
spec:
  provider:
    launchTemplate: MyLaunchTemplate
```

### SubnetSelector

Karpenter discovers subnets using [AWS tags](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html).

Subnets may be specified by any AWS tag, including `Name`. Selecting tag values using wildcards ("\*") is supported.

When launching nodes, Karpenter automatically chooses a subnet that matches the desired zone. If multiple subnets exist for a zone, one is chosen randomly.

**Examples**

Select all subnets with a specified tag:
```
  subnetSelector:
    kubernetes.io/cluster/MyCluster: '*'
```

Select subnets by name:
```
  subnetSelector:
    Name: subnet-0fcd7006b3754e95e
```

Select subnets by an arbitrary AWS tag key/value pair:
```
  subnetSelector:
    MySubnetTag: value
```

Select subnets using wildcards:
```
  subnetSelector:
    Name: *public*

```

### SecurityGroupSelector

The security group of an instance is comparable to a set of firewall rules.
If no security groups are explicitly listed, Karpenter discovers them using the tag "kubernetes.io/cluster/MyClusterName", similar to subnet discovery.

EKS creates at least two security groups by default, [review the documentation](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html) for more info.

Security groups may be specified by any AWS tag, including "name". Selecting tags using wildcards ("*") is supported.

‼️ When launching nodes, Karpenter uses all of the security groups that match the selector. If multiple security groups with the tag `kubernetes.io/cluster/MyClusterName` match the selector, this may result in failures using the AWS Load Balancer controller. The Load Balancer controller only supports a single security group having that tag key. See this [issue](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/2367) for more details.

To verify if this restriction affects you, run the following commands.
```bash
CLUSTER_VPC_ID="$(aws eks describe-cluster --name $CLUSTER_NAME --query cluster.resourcesVpcConfig.vpcId --output text)"

aws ec2 describe-security-groups --filters Name=vpc-id,Values=$CLUSTER_VPC_ID Name=tag-key,Values=kubernetes.io/cluster/$CLUSTER_NAME --query SecurityGroups[].[GroupName] --output text
```

If multiple securityGroups are printed, you will need a more targeted securityGroupSelector.

**Examples**

Select all security groups with a specified tag:
```
spec:
  provider:
    securityGroupSelector:
      kubernetes.io/cluster/MyKarpenterSecurityGroups: '*'
```

Select security groups by name, or another tag (all criteria must match):
```
 securityGroupSelector:
   Name: sg-01077157b7cf4f5a8
   MySecurityTag: '' # matches all resources with the tag
```

Select security groups by name using a wildcard:
```
 securityGroupSelector:
   Name: *public*
```

### Tags

Tags will be added to every EC2 Instance launched by this provisioner.

```
spec:
  provider:
    tags:
      InternalAccountingTag: 1234
      dev.corp.net/app: Calculator
      dev.corp.net/team: MyTeam
```
Note: Karpenter will set the default AWS tags listed below, but these can be overridden in the tags section above.
```
Name: karpenter.sh/cluster/<cluster-name>/provisioner/<provisioner-name>
karpenter.sh/cluster/<cluster-name>: owned
kubernetes.io/cluster/<cluster-name>: owned
```

### Metadata Options

Control the exposure of [Instance Metadata Service](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html) on EC2 Instances launched by this provisioner using a generated launch template.

Refer to [recommended, security best practices](https://aws.github.io/aws-eks-best-practices/security/docs/iam/#restrict-access-to-the-instance-profile-assigned-to-the-worker-node) for limiting exposure of Instance Metadata and User Data to pods.

If metadataOptions are omitted from this provisioner, the following default settings will be used.

```
spec:
  provider:
    metadataOptions:
      httpEndpoint: enabled
      httpProtocolIPv6: disabled
      httpPutResponseHopLimit: 2
      httpTokens: required
```


## Other Resources

### Accelerators, GPU

Accelerator (e.g., GPU) values include
- `nvidia.com/gpu`
- `amd.com/gpu`
- `aws.amazon.com/neuron`

Karpenter supports accelerators, such as GPUs.


Additionally, include a resource requirement in the workload manifest. This will cause the GPU dependent pod will be scheduled onto the appropriate node.

*Accelerator resource in workload manifest (e.g., pod)*

```yaml
spec:
  template:
    spec:
      containers:
      - resources:
          limits:
            nvidia.com/gpu: "1"
```

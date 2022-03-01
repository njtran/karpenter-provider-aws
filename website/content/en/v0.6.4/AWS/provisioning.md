---
title: "Provisioning Configuration"
linkTitle: "Provisioning"
weight: 10
---

## spec.provider

This section covers parameters of the AWS Cloud Provider.

[Review these fields in the code.](https://github.com/aws/karpenter/blob{{< githubRelRef >}}pkg/cloudprovider/aws/apis/v1alpha1/provider.go)

### InstanceProfile
An `InstanceProfile` is a way to pass a single IAM role to an EC2 instance. Karpenter will not create one automatically.
A default profile may be specified on the controller, allowing it to be omitted here. If not specified as either a default
or on the controller, node provisioning will fail.

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

When launching nodes, Karpenter automatically chooses a subnet that matches the desired zone. If multiple subnets exist for a zone, the one with the most available IP addresses will be used.

**Examples**

Select all subnets with a specified tag:
```
  subnetSelector:
    karpenter.sh/discovery/MyClusterName: '*'
```

Select subnets by name:
```
  subnetSelector:
    Name: my-subnet
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

EKS creates at least two security groups by default, [review the documentation](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html) for more info.

Security groups may be specified by any AWS tag, including "Name". Selecting tags using wildcards ("*") is supported.

‼️ When launching nodes, Karpenter uses all of the security groups that match the selector. If multiple security groups with the tag `karpenter.sh/discovery/MyClusterName` match the selector, this may result in failures using the AWS Load Balancer controller. The Load Balancer controller only supports a single security group having that tag key. See this [issue](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/2367) for more details.

To verify if this restriction affects you, run the following commands.
```bash
CLUSTER_VPC_ID="$(aws eks describe-cluster --name $CLUSTER_NAME --query cluster.resourcesVpcConfig.vpcId --output text)"

aws ec2 describe-security-groups --filters Name=vpc-id,Values=$CLUSTER_VPC_ID Name=tag-key,Values=karpenter.sh/discovery/$CLUSTER_NAME --query 'SecurityGroups[].[GroupName]' --output text
```

If multiple securityGroups are printed, you will need a more targeted securityGroupSelector.

**Examples**

Select all security groups with a specified tag:
```
spec:
  provider:
    securityGroupSelector:
      karpenter.sh/discovery/MyClusterName: '*'
```

Select security groups by name, or another tag (all criteria must match):
```
 securityGroupSelector:
   Name: my-security-group
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

### Amazon Machine Image (AMI) Family

The AMI used when provisioning nodes can be controlled by the `amiFamily` field. Based on the value set for `amiFamily`, Karpenter will automatically query for the appropriate [EKS optimized AMI](https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-amis.html) via AWS Systems Manager (SSM). 

Currently, Karpenter supports `amiFamily` values `AL2`, `Bottlerocket`, and `Ubuntu`. GPUs are only supported with `AL2` and `Bottlerocket`.

Note: If a custom launch template is specified, then the AMI value in the launch template is used rather than the `amiFamily` value.


```
spec:
  provider:
    amiFamily: Bottlerocket
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

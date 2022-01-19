---
title: "Development Guide"
linkTitle: "Development Guide"
weight: 80
---

## Dependencies

The following tools are required for contributing to the Karpenter project.

| Package                                                            | Version  | Install                                        |
| ------------------------------------------------------------------ | -------- | ---------------------------------------------- |
| [go](https://golang.org/dl/)                                       | v1.15.3+ | [Instructions](https://golang.org/doc/install) |
| [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) |          | `brew install kubectl`                         |
| [helm](https://helm.sh/docs/intro/install/)                        |          | `brew install helm`                            |
| Other tools                                                        |          | `make toolchain`                               |

## Developing

### Setup / Teardown

Based on how you are running your Kubernetes cluster, follow the [Environment specific setup](#environment-specific-setup) to configure your environment before you continue. Once you have your environment set up, to install Karpenter in the Kubernetes cluster specified in your `~/.kube/config`  run the following commands.

```
CLOUD_PROVIDER=<YOUR_PROVIDER> make apply # Install Karpenter
make delete # Uninstall Karpenter
```

### Developer Loop
* Make sure dependencies are installed
    * Run `make codegen` to make sure yaml manifests are generated
    * Run `make toolchain` to install cli tools for building and testing the project
* You will need a personal development image repository (e.g. ECR)
    * Make sure you have valid credentials to your development repository.
    * `$KO_DOCKER_REPO` must point to your development repository
    * Your cluster must have permissions to read from the repository
* It's also a good idea to persist `$CLOUD_PROVIDER` in your environment variables to simplify the `make apply` command.

### Build and Deploy
*Note: these commands do not rely on each other and may be executed independently*
```sh
make apply # quickly deploy changes to your cluster
make dev # run codegen, lint, and tests
```

### Testing
```sh
make test       # E2e correctness tests
make battletest # More rigorous tests run in CI environment
```

### Verbose Logging
```sh
kubectl patch configmap config-logging -n karpenter --patch '{"data":{"loglevel.controller":"debug"}}'
```

### Debugging Metrics
OSX:
```sh
open http://localhost:8080/metrics && kubectl port-forward service/karpenter-metrics -n karpenter 8080
```

Linux:
```sh
gio open http://localhost:8080/metrics && kubectl port-forward service/karpenter-metrics -n karpenter 8080
```

### Tailing Logs
While you can tail Karpenter's logs with kubectl, there's a number of tools out there that enhance the experience. We recommend [Stern](https://pkg.go.dev/github.com/planetscale/stern#section-readme):

```sh
stern -l karpenter=controller -n karpenter
```

## Environment specific setup

### AWS
Set the CLOUD_PROVIDER environment variable to build cloud provider specific packages of Karpenter.

```sh
export CLOUD_PROVIDER=aws
```

For local development on Karpenter you will need a Docker repo which can manage your images for Karpenter components.
You can use the following command to provision an ECR repository.
```sh
aws ecr create-repository \
    --repository-name karpenter/controller \
    --image-scanning-configuration scanOnPush=true \
    --region ${AWS_DEFAULT_REGION}
aws ecr create-repository \
    --repository-name karpenter/webhook \
    --image-scanning-configuration scanOnPush=true \
    --region ${AWS_DEFAULT_REGION}
```

Once you have your ECR repository provisioned, configure your Docker daemon to authenticate with your newly created repository.

```sh
export KO_DOCKER_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/karpenter"
aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin $KO_DOCKER_REPO
```

# kubectl-eks

Action to apply artifacts files in your [EKS](https://aws.amazon.com/pt/eks/) cluster.

This action enables you to apply kubernetes artifacts files just pointing the path where your file is.

<br>

# Example
```yml
name: Build

on:
  push:
    branches: [ main ]

  deploy:
    runs-on: ubuntu-latest
    steps:
      -
        name: Checkout 
        uses: actions/checkout@v2
      -
        name: Deployment
        uses: Pablommr/kubectl-eks@v1.0.0
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          KUBECONFIG: ${{ secrets.KUBECONFIG }}
          KUBE_YAML: path_to_file/file.yml
```


<br>

# Usage
To use this action, you just need a user that have heve permission to apply artifacts in your EKS cluster (More info see in this [link](https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html)), and setup some ENV's variables listed next.

<br>

# ENV's

## Required

### `AWS_ACCESS_KEY_ID`

AWS access key id for IAM role.

### `AWS_SECRET_ACCESS_KEY`

AWS secret key for IAM role. 

### `KUBECONFIG`

Environment variable name containing base64-encoded kubeconfig data. Need atention with profile name that must be the same in AWS_PROFILE_NAME.

### `KUBE_YAML`

Path to file used to create/update the resource.

<br>

## Optional

### `AWS_PROFILE_NAME`

Profile name to be configured. If not passed, this env assume the value 'default'

### `ENVSUBST`
(boolean)

Whether to run envsubst to substitute environment variables inside the file in KUBE_YAML. Your variable inside your file need begin with "$". If not passed, this env assume the value 'false'

### `KUBE_ROLLOUT`
(boolean)

Whether to watch the status of the latest rollout until it's done. The rollout onlly works to deployment/statefulset/daemonset and only be executed if the POD's applyed by KUBE_YAML finalize with unchaged status.

<br>

# Use case

Let's suppose you need apply 3 artifacts in you EKS, one deployment, one service, and one configmap, add all your kubernetes artifacts are inside in folder kubernetes, some like this:

```
├── README.md
├── app
|  └── files
├── kubernetes
|  ├── service.yml
|  ├── configmap.yaml
|  └── deployment.yml
└── another_files
```
You already set up your build and just need apply in your kubernetes. You have the premise that always the pipeline run, even that change was in the configmap for exemple, you will need rollout the pods, and you will need too substitute your variables inside deployment.yml for some another value. Let's assume you want to change the image tag, so you can name your tag in image line in deployment.yml with some name, for example $IMAGE_TAG, like this:

```
image: nginx:$IMAGE_TAG
```

And then pass the IMAGE_TAG as a env with value wished. 

 So, you can configure your pipeline in this way:



```yml
name: Build

on:
  push:
    branches: [ main ]

  workflow_dispatch:

env:
  AWS_PROFILE_NAME: default
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  KUBECONFIG: ${{ secrets.KUBECONFIG }}

  deploy:
    runs-on: ubuntu-latest
    needs: build_and_push
    steps:
      -
        name: Checkout 
        uses: actions/checkout@v2
      -
        name: Service
        uses: Pablommr/kubectl-eks@v1.0.0
        env:
          KUBE_YAML: kubernetes/service.yml
      -
        name: Configmap
        uses: Pablommr/kubectl-eks@v1.0.0
        env:
          KUBE_YAML: kubernetes/configmap.yml
      -
        name: Deployment
        uses: Pablommr/kubectl-eks@v1.0.0
        env:
          KUBE_YAML: kubernetes/deployment.yml
          ENVSUBST: true
          KUBE_ROLLOUT: true
          IMAGE_TAG: 1.21.6
```
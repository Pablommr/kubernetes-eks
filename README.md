# kubernetes-eks

Action to apply artifacts files in your [EKS](https://aws.amazon.com/pt/eks/) cluster.

This action allows you to apply Kubernetes artifact files by simply pointing to the path where your file is located.

<br>

# Example
```yml
name: Build

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      -
        name: Checkout 
        uses: actions/checkout@v4
      -
        name: Deployment
        uses: Pablommr/kubernetes-eks@v2.0.1
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          KUBECONFIG: ${{ secrets.KUBECONFIG }}
          KUBE_YAML: path_to_file/file.yml
```


<br>

# Usage
To use this action, you just need a user that has permission to apply artifacts in your EKS cluster. For more information, see this [link](https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html). Also, set up the necessary environment variables listed below.

<br>

# ENV's

## Required

### `AWS_ACCESS_KEY_ID`

AWS access key id for IAM role.

### `AWS_SECRET_ACCESS_KEY`

AWS secret key for IAM role. 

### `KUBECONFIG`

Environment variable containing the base64-encoded kubeconfig data. Pay attention to the profile name; it must match the AWS_PROFILE_NAME.

### `KUBE_YAML` or `FILES_PATH`

One of them (or both) must be set. <br><br>
KUBE_YAML is the path of <b>file</b> to file used to create/update the resource. This env can be an array with more then 1 file. (I.e. kubernetes/deployment.yml,artifacts/configmap.yaml )<br>
FILES_PATH is the path of the <b>directory</b> where the files are located. All files in this directory will be applied.<br><br>
The files must be with *.yaml or *.yml extensions.

<br>

## Optional

### `AWS_PROFILE_NAME`

Profile name to be configured. If not passed, this env assume the value 'default'

### `ENVSUBST`
(boolean)

Whether to run envsubst to substitute environment variables inside the file in KUBE_YAML. Your variable inside your file need begin with "$". If not passed, this env assume the value 'false'

### `SUBPATH`
(boolean)

If you use path in env FILES_PATH, you can set this env to true to apply files in subdirectory. Default value is false.

### `CONTINUE_IF_FAIL`
(boolean)

If you use path in env FILES_PATH, you can set this env to true to continue applying files in case of fail in one file. Default value is false.

### `KUBE_ROLLOUT`
(boolean)

Whether to watch the status of the latest rollout until it's done. The rollout only works for Deployment, StatefulSet, or DaemonSet resources and will only be executed if the Pods applied by KUBE_YAML finalize with an unchanged status.

<br>

# Use case

Let's suppose you need to apply three artifacts in your EKS: one Deployment, one Service, and one ConfigMap. All your Kubernetes artifacts are inside the kubernetes folder, like this:

```
├── README.md
├── app
|  └── files
├── kubernetes
│   ├── deployment.yaml
│   ├── envs
│   │   ├── prod
│   │   │   └── configmap.yaml
│   │   └── staging
│   │       └── configmap.yaml
│   └── service.yaml
└── another_files
```
You've already set up your build and just need to apply it in Kubernetes. Even if the only change was in the ConfigMap, you will need to roll out the pods. You want to apply just the prod ConfigMap, and you also need to substitute variables inside deployment.yml for some other value. Let's assume you want to change the image tag, so you can name your tag in the image line in deployment.yml with a placeholder, for example $IMAGE_TAG, like this:

```
image: nginx:$IMAGE_TAG
```

Then, pass the IMAGE_TAG as an environment variable with the desired value.

You can configure your pipeline like this:

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

jobs:
  deploy:
    runs-on: ubuntu-latest
    needs: build_and_push
    steps:
      - name: Checkout 
        uses: actions/checkout@v4
      - name: Deploy
        uses: Pablommr/kubernetes-eks@v2.0.1
        env:
          FILES_PATH: kubernetes
          KUBE_YAML: kubernetes/envs/configmap.yaml
          SUBPATH: false #Defaul value
          ENVSUBST: true
          KUBE_ROLLOUT: true
          IMAGE_TAG: 1.21.6
```

In this setup, with FILES_PATH: kubernetes, you will apply all files under the kubernetes path (deployment.yaml and service.yaml), but none under env, since SUBPATH is set to false. However, you will still apply the ConfigMap with KUBE_YAML: kubernetes/envs/configmap.yaml.

<br>

# Change Log

## v2.0.1

- Fix to get resource name
- Add yq in background

## v2.0.0

- Added possibilitie to add path (env FILES_PATH) to apply multiple files
- Added env SUBPATH to apply files in supath
- Added env CONTINUE_IF_FAIL to continue applying files in fail case
- Added output on github action page

## v1.2.0

- Changed strategy to use an image that has already been built with dependencies in public registry [kubernetes-eks](https://hub.docker.com/r/pablommr/kubernetes-eks), decreasing action execution time

## v1.1.0

- Added otpion to KUBE_ROLLOUT follow the rollout status in Action page
- Fix metacharacter replacement in ENVSUBST

## v1.0.0
- Project started
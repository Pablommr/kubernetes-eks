#!/bin/bash

#set -e
#
#echo "Checking ENVs..."
#
##Check if ENVs is fulfiled
#if [ -z "$AWS_ACCESS_KEY_ID" ]
#then
#  echo 'Env AWS_ACCESS_KEY_ID is empty! Please, fulfil it with your aws access key...'
#  exit 1
#elif [ -z "$AWS_SECRET_ACCESS_KEY" ]
#then
#  echo 'Env AWS_SECRET_ACCESS_KEY is empty! Please, fulfil  with your aws access secret...'
#  exit 1
#elif [ -z "$KUBECONFIG" ]
#then
#  echo 'Env KUBECONFIG is empty! Please, fulfil it with your kubeconfig in base64...'
#  exit 1
#elif [ ! -e "$(eval echo $KUBE_YAML)" ]
#then
#  echo "Env KUBE_YAML is empty or file doesn't exist! Please, fulfil it with full path where your file is..."
#  exit 1
#elif [ -z "$AWS_PROFILE_NAME" ]
#then
#  AWS_PROFILE_NAME='default'
#  echo 'Env AWS_PROFILE_NAME is empty! Using default.'
#else
#  echo 'Envs filled!'
#fi
#
#echo ""
#
#mkdir -p ~/.aws
#mkdir -p ~/.kube
#
#AWS_CREDENTIALS_PATH='~/.aws/credentials'
#KUBECONFIG_PATH='~/.kube/config'
#
##fulfiling the files
#echo "[$AWS_PROFILE_NAME]" > $(eval echo $AWS_CREDENTIALS_PATH)
#echo "aws_access_key_id = $AWS_ACCESS_KEY_ID" >> $(eval echo $AWS_CREDENTIALS_PATH)
#echo "aws_secret_access_key = $AWS_SECRET_ACCESS_KEY" >> $(eval echo $AWS_CREDENTIALS_PATH)
#
#echo "$KUBECONFIG" |base64 -d > $(eval echo $KUBECONFIG_PATH)
#
##Unset var to make sure ther are no conflict
#unset KUBECONFIG
#
##Alter files if ENVSUBS=true
#if [ "$ENVSUBST" = true ]; then
#
#  for ENV_VAR in $(env |cut -f 1 -d =); do
#    VAR_KEY=$ENV_VAR
#    VAR_VALUE=$(eval echo \$$ENV_VAR | sed -e 's/\//\\&/g;s/\&/\\&/g;')
#    sed -i "s/\$$VAR_KEY/$VAR_VALUE/g" $KUBE_YAML
#  done
#
#fi
#
#echo "Applying file:"
#
##Applying artifact
#KUBE_APPLY=$(kubectl apply -f $KUBE_YAML)
#echo $KUBE_APPLY
#
##Verify and execute rollout
#if [ "$KUBE_ROLLOUT" == true ] && [ "$(echo $KUBE_APPLY |sed 's/.* //')" == "unchanged" ]; then
#  echo ""
#  echo "Applying rollout:"
#  kubectl rollout restart --filename $KUBE_YAML
#  echo ""
#  echo "Checking rollout status:"
#  kubectl rollout status --filename $KUBE_YAML
#elif [ "$KUBE_ROLLOUT" = true ] && ([ "$(echo $KUBE_APPLY |sed 's/.* //')" == "configured" ] || [ "$(echo $KUBE_APPLY |sed 's/.* //')" == "created" ]); then
#  echo ""
#  echo "Checking rollout status:"
#  kubectl rollout status --filename $KUBE_YAML
#fi
#
#echo ""
#
#echo "All done! =D"


###Tratar e retirar / no final
FILES_PATH="kubernetes"

#Lista de arquivos
FILES_YAML=($(ls $FILES_PATH))

FILES_JSON='{}'

#Percorre os arquivos para montar o FILES_JSON com os arquivos
for i in ${FILES_YAML[@]}; do
  kind="$(sed -n '/^kind: /{p; q;}' $FILES_PATH/$i | cut -d ':' -f2 | tr -d ' ')"
  FILES_JSON="$(echo -n $FILES_JSON | jq -cr "(select(.cliente == \"$kind\") // .$kind | .files) += [\"$i\"]")"
done

echo "| Type        | Files   | Status  |" >> $GITHUB_STEP_SUMMARY
echo "|-------------|---------|---------|" >> $GITHUB_STEP_SUMMARY

#Percorre JSON para aplicar os arquivos
for type in $(echo -n "$FILES_JSON" | jq -cr 'keys[]'); do

  echo -n "| $type | " >> $GITHUB_STEP_SUMMARY
  for files in $(echo -n "$FILES_JSON" | jq -cr ".$type.files[]"); do
    echo "| $Files | " >> $GITHUB_STEP_SUMMARY
  done
  echo "| Passed :white_check_mark: |" >> $GITHUB_STEP_SUMMARY
done
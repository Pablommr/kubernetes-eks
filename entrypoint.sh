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

echo ""

mkdir -p ~/.aws
mkdir -p ~/.kube

AWS_CREDENTIALS_PATH='~/.aws/credentials'
KUBECONFIG_PATH='~/.kube/config'

#fulfiling the files
echo "[$AWS_PROFILE_NAME]" > $(eval echo $AWS_CREDENTIALS_PATH)
echo "aws_access_key_id = $AWS_ACCESS_KEY_ID" >> $(eval echo $AWS_CREDENTIALS_PATH)
echo "aws_secret_access_key = $AWS_SECRET_ACCESS_KEY" >> $(eval echo $AWS_CREDENTIALS_PATH)

echo "$KUBECONFIG" |base64 -d > $(eval echo $KUBECONFIG_PATH)

#Unset var to make sure ther are no conflict
unset KUBECONFIG
#
#
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

#Cria Json com arquivos a serem aplicados
createJsonFiles () {
  local file="$1"
  local kind="$(sed -n '/^kind: /{p; q;}' $file | cut -d ':' -f2 | tr -d ' ')"

  #Folder que será usado para amarzernar os arquivos splitados
  local folder_split='csplit'

  #Verifica se tem '---' na primeira linha, e caso tenha, remove
  if [ "$(head -1 $file)" == "---" ]; then
    sed -i '1d' $file
  fi

  if [ $(grep "^---$" "$file" | wc -l) -ne 0 ]; then
    #cria o diretório csplit
    mkdir -p $folder_split
    #Não funciona no MacOS
    csplit "$(date +%s%N | cut -b1-9)_artifact_" --suffix-format="%02d.yaml" "$file" "/---/" "{*}" > /dev/null 2>&1
    #Move os novos arquivos criados
    mv *_artifact_* $folder_split
    #Remove o arquivo com ---
    rm $file

    ls $folder_split

    #Lista dos novos arquivos
    local NEW_FILES_YAML=($(find $folder_split -type f \( -name "*.yml" -o -name "*.yaml" \) | paste -sd ' ' -))

    echo "echo NEW_FILES_YAML"
    echo ${NEW_FILES_YAML[@]}

    #Percorre os novos arquivos
    for j in ${NEW_FILES_YAML[@]}; do
      createJsonFiles $j
    done

  else
    FILES_JSON="$(echo -n $FILES_JSON | jq -cr "(select(.cliente == \"$kind\") // .$kind | .files) += [\"$file\"]")"
  fi
}

envSubstitution () {
  local file="$1"

  for ENV_VAR in $(env |cut -f 1 -d =); do
    local VAR_KEY=$ENV_VAR
    local VAR_VALUE=$(eval echo \$$ENV_VAR | sed -e 's/\//\\&/g;s/\&/\\&/g;')
    sed -i "s/\$$VAR_KEY/$VAR_VALUE/g" $file
  done
}

applyFile () {
  local file="$1"

  #Applying artifact
  echo "Applying file: $file"
  KUBE_APPLY=$(kubectl apply -f $file)
  echo $KUBE_APPLY
}

###=============

#envs de usuário
FILES_PATH="kubernetes"
SUBPATH=true
KUBE_YAML=()



# Verifica se o último caractere é uma barra (/)
if [[ "$FILES_PATH" == */ ]]; then
  # Remove a barra (/) do final
  FILES_PATH=${FILES_PATH%/}
fi

#Lista de arquivos
FILES_YAML=($(find $FILES_PATH -type f \( -name "*.yml" -o -name "*.yaml" \) | paste -sd ' ' -))

FILES_JSON='{}'

#Adiciona arquivos individuais setados pelo usuário
FILES_YAML+=("${KUBE_YAML[@]}")

#Percorre os arquivos para montar o FILES_JSON com os arquivos
for i in ${FILES_YAML[@]}; do

  #Remove da string o path informado pelo usuário
  files_relative=$(echo "$i" | sed "s|$FILES_PATH/||")

  # Conta o número de barras (/) no caminho e subtrai 1 para obter o número de sub-diretórios
  num_directories=$(echo "$files_relative" | tr -cd '/' | wc -c)

  if $SUBPATH; then
    #cria Json com todos os arquivos do diretório e sub-diretório
    createJsonFiles $i
  else
    #Verifica se tem mais sub-diretórios além do informado
    if [ $num_directories -gt 0 ]; then
      echo "Ignorando arquivo $i"
    else
      createJsonFiles $i
    fi
  fi
done


echo "| Type        | Files   | Status  |" >> $GITHUB_STEP_SUMMARY
echo "|-------------|---------|---------|" >> $GITHUB_STEP_SUMMARY

#Percorre JSON para aplicar os arquivos
for type in $(echo -n "$FILES_JSON" | jq -cr 'keys[]'); do

  echo "Type: $type"
  echo -n "| $type | " >> $GITHUB_STEP_SUMMARY  #Debug
  for file in $(echo -n "$FILES_JSON" | jq -cr ".$type.files[]"); do
    echo "File: $file"  #Debug
    echo -n "$file <br>" >> $GITHUB_STEP_SUMMARY

    #Alter files if ENVSUBS=true
    if [ "$ENVSUBST" = true ]; then
      envSubstitution $file
    fi

    #Apply file
    applyFile $file
  done
  echo " | Passed :white_check_mark: |" >> $GITHUB_STEP_SUMMARY
done
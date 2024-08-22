#!/bin/bash

#set -e
#
echo ""
echo "Checking ENVs..."

#Check if ENVs is fulfiled
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
  echo 'Env AWS_ACCESS_KEY_ID is empty! Please, fulfil it with your aws access key...'
  exit 1
elif [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  echo 'Env AWS_SECRET_ACCESS_KEY is empty! Please, fulfil  with your aws access secret...'
  exit 1
elif [ -z "$KUBECONFIG" ]; then
  echo 'Env KUBECONFIG is empty! Please, fulfil it with your kubeconfig in base64...'
  exit 1
elif [ -z "$KUBE_YAML" ]; then
  if [ -z "$FILES_PATH" ]; then
    echo "Envs KUBE_YAML or FILES_PATH is empty or file doesn't exist! Please, fulfil it with full path where your file is..."
    exit 1
  else
    echo 'Envs filled!'
    echo ""
  fi
fi

if [ -z "$AWS_PROFILE_NAME" ]; then
  AWS_PROFILE_NAME='default'
  echo 'Env AWS_PROFILE_NAME is empty! Using default.'
fi
if [ -z "$ENVSUBST" ]; then
  ENVSUBST=false
  echo 'Env ENVSUBST is empty! Using default=false.'
fi
if [ "$SUBPATH" != "true" ] && [ "$SUBPATH" != "false" ]; then
  SUBPATH=false
  echo 'Env SUBPATH is empty ow wrong value! Using default=false.'
fi
if [ -z "$CONTINUE_IF_FAIL" ] || [ "$CONTINUE_IF_FAIL" = "true" ] || [ "$CONTINUE_IF_FAIL" = "false" ]; then
  CONTINUE_IF_FAIL=false
  echo 'Env CONTINUE_IF_FAIL is empty! Using default=false.'
fi
if [ -z "$KUBE_ROLLOUT" ] || [ "$KUBE_ROLLOUT" = "true" ] || [ "$KUBE_ROLLOUT" = "false" ]; then
  KUBE_ROLLOUT=true
  echo 'Env KUBE_ROLLOUT is empty! Using default=true.'
fi

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

#Cria Json com arquivos a serem aplicados
createJsonFiles () {
  #Local do arquivo a ser aplicado
  local file="$1"
  #Env que será usada para realizar o print na página do Actions
  local name_file="$2"
  local kind="$(sed -n '/^kind: /{p; q;}' $file | cut -d ':' -f2 | tr -d ' ')"

  #Folder que será usado para amarzernar os arquivos splitados
  local folder_split='csplit'
  local tmp_dir='tmp_dir'

  #Verifica se tem '---' na primeira linha, e caso tenha, remove
  if [ "$(head -1 $file)" == "---" ]; then
    sed -i '1d' $file
  fi

  if [ $(grep "^---$" "$file" | wc -l) -ne 0 ]; then
    #cria o diretório csplit
    mkdir -p $folder_split
    mkdir -p $tmp_dir
    #Não funciona no MacOS
    csplit --prefix="$(uuidgen | cut -c1-4)_artifact_" --suffix-format="%02d.yaml" "$file" "/---/" "{*}" > /dev/null 2>&1
    #Move os novos arquivos criados
    cp *_artifact_* $folder_split
    #Esse tmp existe para o find procurar em um lugar único, se não, ele sempre lista tudo do diretório atual
    cp *_artifact_* $tmp_dir
    #Remove o arquivo com ---
    rm $file
    #Remove arquivos que já foram copiados para não dar duplicidade
    rm -rf *_artifact_*

    #Lista dos novos arquivos
    local NEW_FILES_YAML=($(find $tmp_dir -type f \( -name "*.yml" -o -name "*.yaml" \) | paste -sd ' ' -))

    #Remove arquivos locais para não haver repetição na próxima iteração
    rm -rf $tmp_dir

    #Percorre os novos arquivos
    for j in ${NEW_FILES_YAML[@]}; do
      createJsonFiles "$(echo -n $j | sed 's/tmp_dir/csplit/')" $file
    done

  else
    #Verifica se a env que printa está vazia
    if [ -z "$name_file" ]; then
      local name_file="$file"
    fi

    #Adiciona no Json o arquivo
    FILES_JSON="$(echo -n $FILES_JSON | jq -cr "(.$kind | .files) += [{"file":\"$file\","print":\"$name_file\"}]")"
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

artifactType () {
  local type="$1"
  local kube_rollout="$2"

  echo "Type: $type"
  echo -n "| $type | " >> $GITHUB_STEP_SUMMARY

  #Usado para formatar o output na página do github Action
  tmp_count=0
  for json_file in $(echo -n "$FILES_JSON" | jq -cr ".$type.files[]"); do
    local file="$(echo -n $json_file | jq -cr '.file')"
    local print_name="$(echo -n $json_file | jq -cr '.print')"

    #Alter files if ENVSUBS=true
    if [ "$ENVSUBST" = true ]; then
      envSubstitution $file
    fi

    #Apply file
    applyFile $file $print_name $tmp_count $kube_rollout
    #Incrementa o Count
    tmp_count=$((tmp_count + 1))
  done
}

applyFile () {
  local file="$1"
  local print_name="$2"
  local tmp_count="$3"
  local kube_rollout="$4"

  #Printa em branco na primeira tabela caso seja outro arquivo do mesmo tipo
  if [ $tmp_count -gt 0 ]; then
    echo -n "| | " >> $GITHUB_STEP_SUMMARY
  fi

  #Applying artifact
  echo "Applying file: $file"
  echo "Original file: $print_name"
  echo -n "$print_name" >> $GITHUB_STEP_SUMMARY
  KUBE_APPLY=$(kubectl apply -f $file 2>&1)
  KUBE_EXIT_CODE=$?
  if [ $KUBE_EXIT_CODE -ne 0 ]; then
    echo "Erro ao aplicar o arquivo $file:"
    echo " | Failed :x: |" >> $GITHUB_STEP_SUMMARY
    #Para a action caso o esteja setado CONTINUE_IF_FAIL=false
    echo "KUBE_EXIT_CODE: $KUBE_EXIT_CODE"
    if ! $CONTINUE_IF_FAIL; then
      exit 1
    fi
  else
    echo "Arquivo aplicado com sucesso: $file"
    echo " | Passed :white_check_mark: |" >> $GITHUB_STEP_SUMMARY
  fi

  #Verify and execute rollout
  if [ "$kube_rollout" == true ] && [ "$(echo $KUBE_APPLY |sed 's/.* //')" == "unchanged" ]; then
    echo ""
    echo "Applying rollout:"
    kubectl rollout restart --filename $KUBE_YAML
    echo ""
    echo "Checking rollout status:"
    kubectl rollout status --filename $KUBE_YAML
  elif [ "$kube_rollout" = true ] && ([ "$(echo $KUBE_APPLY |sed 's/.* //')" == "configured" ] || [ "$(echo $KUBE_APPLY |sed 's/.* //')" == "created" ]); then
    echo ""
    echo "Checking rollout status:"
    kubectl rollout status --filename $KUBE_YAML
  fi

  echo "$KUBE_APPLY"
  echo "============================="
}

###===========================================================
###===========================================================
###===========================================================

#Transformando os inputs do githubaciotns em array
IFS=',' read -r -a FT_FILES_PATH <<< "$FILES_PATH"
IFS=',' read -r -a FT_KUBE_YAML <<< "$KUBE_YAML"

# Loop para iterar sobre cada item no vetor
for i in "${!FT_FILES_PATH[@]}"; do
  if [[ "${FT_FILES_PATH[$i]}" == */ ]]; then
    # Remove a barra (/) do final
    FT_FILES_PATH[$i]="${FT_FILES_PATH[$i]%/}"
  fi
done

for j in "${!FT_FILES_PATH[@]}"; do
  #Lista de arquivos
  FILES_YAML+=($(find ${FT_FILES_PATH[$j]} -type f \( -name "*.yml" -o -name "*.yaml" \) | paste -sd ' ' -))
done

FILES_JSON='{}'

#Adiciona arquivos individuais setados pelo usuário
FILES_YAML+=("${FT_KUBE_YAML[@]}")

#Percorre os arquivos para montar o FILES_JSON com os arquivos
for i in ${FILES_YAML[@]}; do

  if $SUBPATH; then
    #cria Json com todos os arquivos do diretório e sub-diretório
    createJsonFiles $i
  else
    #Quantidade total de subpath no arquivo a ser aplicado
    qtd_path_file=$(echo "$i" | tr -cd '/' | wc -c | tr -d ' ')
    #Percorre cada arquivo para contar a quantidade de path
    for path in "${FT_FILES_PATH[@]}"; do
      #Retira o path informado pelo usuário do path total do arquivo
      file_no_path=$(echo "$i" | sed "s|^$path/||")
      #Verifica se o arquivo a ser aplicado tem em seu path um dos path (em caso de vetor) informado pelo usuário
      if [ "$i" != "$file_no_path" ];then
        qtd_subpath=$(echo "$file_no_path" | tr -cd '/' | wc -c | tr -d ' ')
      fi
    done
    #Verifica se tem mais sub-diretórios além do informado
    echo "qtd_subpath: $qtd_subpath | qtd_path_file: $qtd_path_file"
    echo "i: $i"
    if [ $qtd_subpath -gt $qtd_path_file ]; then
      #VERIFICAR SE O ARQUIVO $I EXISTE NO VETOR ${FT_KUBE_YAML[@]}
      echo "SUBPATH=false. Ignoring file: $i"
    else
      createJsonFiles $i
    fi
  fi
done

echo ""


echo "| Type        | Files   | Status  |" >> $GITHUB_STEP_SUMMARY
echo "|-------------|---------|---------|" >> $GITHUB_STEP_SUMMARY

echo "Files to apply:"
echo $FILES_JSON | jq
echo "============================="


#Verifica se tem artefatos do tipo Namespace para aplicar primeiro
if echo -n "$FILES_JSON" | jq -e '.Namespace' > /dev/null; then
  artifactType "Namespace" false
fi

#Percorre todos os tipos de artefatos
for type in $(echo -n "$FILES_JSON" | jq -cr 'keys[]'); do
  #Verifica se o type não é o tipo Namespace, que já foi aplicado, e se não são artefatos que contém pod para aplicar por último
  if [[ "$type" != "Namespace" ]] && \
     [[ "$type" != "Deployment" ]] && \
     [[ "$type" != "ReplicaSet" ]] && \
     [[ "$type" != "DaemonSet" ]] && \
     [[ "$type" != "Pod" ]]; then
    artifactType $type false
  fi
done

#Aplica os últimos artefatos que tem Pods
last_apply=(
  "Deployment"
  "ReplicaSet"
  "DaemonSet"
  "Pod"
)

for type in $last_apply; do
  if [ "$KUBE_ROLLOUT" = true ]; then
    artifactType $type true
  else
    artifactType $type false
  fi
done


echo ""
echo "All done! =D"
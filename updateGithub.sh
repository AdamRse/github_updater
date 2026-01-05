#!/bin/bash

# SYSTEMD
# Nom du service : update-github.service
# Pour modifier $HOUR_LIMIT, il faut redémarrer les service pour être pris en compte :
# sudo systemctl restart update-github.service
#
# Logs : journalctl -u update-github.service -f

# -- VARIABLES --

script_path=$(readlink -f "$0")
script_dir=$(dirname "${script_path}")
env_location="${script_dir}/.env"
required_env_vars=(
    "USERNAME"
    "API_URL"
    "REPO_PATH"
    "HOUR_LIMIT"
    "QUOTES_FILE"
    "QUOTE_OUTPUT_FILE"
)

# -- CHECKS --

# Packages
need_package=""
for cmd in curl jq git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [ -z "${need_package}" ]; then
      need_package="${cmd} n'est pas installé"
    else
      need_package="${need_package}\n${cmd} n'est pas installé"
    fi
  fi
done
if [ -n "${need_package}" ]; then
  echo -e "ERREUR : Les paquets suivants sont nécéssaire :\n${need_package}\n\nFin du programme." >&2
  exit 1
fi

# Environment
if [ ! -f "${env_location}" ]; then
  echo "ERREUR: Impossible de trouver le fichier des variables d'environnement. Fichier recherché : '${env_location}'" >&2
  exit 1
fi
source "${env_location}"
env_var_missing=""
for var in "${required_env_vars[@]}"; do
  if [ -z "${!var}" ]; then
    if [ -z "${env_var_missing}" ]; then
      env_var_missing="Erreur, il manque des variables dans de .env ('${env_location}')\n\tLa variable ${var} est requise"
    else
      env_var_missing="${env_var_missing}\n\tLa variable ${var} est requise"
    fi
  fi
done
if [ -n "${env_var_missing}" ]; then
  echo -e "${env_var_missing}" >&2
  exit 1
fi

# Other
if [ ! -d "${REPO_PATH}" ]; then
  echo "ERREUR: Impossible d'accéder à '${REPO_PATH}'" >&2
  exit 1
fi

if ! git -C "${REPO_PATH}" rev-parse --git-dir > /dev/null 2>&1; then
  echo "ERREUR: '${REPO_PATH}' n'est pas un repository git" >&2
  exit 1
fi

# -- FONCTIONS --

# Fonction pour obtenir une citation aléatoire
obtenir_citation_aleatoire() {
  [ -z "$1" ] && echo "obtenir_citation_aleatoire() ERREUR : 1 paramètre requis pour le chemin du fichier" >&2 && return 1

  local QUOTES_FILE_loc=$1
  local id=$(date +%s%N | md5sum | head -c20)

  # Vérifier si le fichier de citations existe
  if [ ! -f "${QUOTES_FILE_loc}" ]; then
    echo "ERREUR: ${id}" >&2
    echo "Erreur : Le fichier ${QUOTES_FILE_loc} n'existe pas" >&2
    return 1
  fi

  local nombre_citations=$(grep -c "\*\*/" "${QUOTES_FILE_loc}")

  # Si on a bien un vombre positif de citations
  if [[ "${nombre_citations}" =~ ^[0-9]+$ ]] && (( nombre_citations > 0 )); then
    # Générer un nombre aléatoire entre 1 et le nombre de citations
    local index_aleatoire=$((RANDOM % nombre_citations + 1))

    # Extraire la citation choisie
    local citation=$(awk -v num="${index_aleatoire}" 'BEGIN{RS="**/"} NR==num {print}' "${QUOTES_FILE_loc}")

    # Nettoyer la citation
    citation=$(echo "${citation}" | tr -d '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Retourner la citation avec l'ID
    echo "${citation}

    /$id/"
  else
    echo -e "WARNING obtenir_citation_aleatoire() : Citations introuvables\n\tVariable : ${nombre_citations}  ID : ${id}" >&2
  fi
}
get_last_commit_date() {
  local response
  if ! response=$(curl -s --max-time 10 "${API_URL}" 2>/dev/null); then
    echo "Erreur get_last_commit_date : Impossible de contacter l'API GitHub" >&2
    return 1
  fi
  
  echo "${response}" \
  | jq -r '
    .[]
    | select(.type == "PushEvent")
    | select(.actor.login == "$USERNAME")
    | .created_at
    | select(. != null)
    ' \
  | head -n 1;
}
make_change_and_commit() {
  local error_msg="";
  obtenir_citation_aleatoire "${QUOTES_FILE}" > "${QUOTE_OUTPUT_FILE}" || error_msg="Impossible de remplacer le fichier de citation '${QUOTE_OUTPUT_FILE}'"
  local commit_id="$(date +%s%N | md5sum | head -c5)"
  git add . && git commit -m "${commit_id}" || error_msg="Erreur lors de la création du commit ${commit_id}"

  if [ -z "${error_msg}" ]; then
    return 0
  else
    echo "ERREUR make_change_and_commit() : ${error_msg}" >&2
    return 1
  fi
}
send_commit() {
  local error_msg=""
  cd "${REPO_PATH}"
  if git pull; then
    if make_change_and_commit; then
      git push || error_msg="git push impossible."
    else
      error_msg="commit local échoué."
    fi
  else
    error_msg="git pull a échoué.\n\t-création du commit"
    make_change_and_commit && echo "Le git pull a échoué mais le commit a bien été effectué en lcoal." || error_msg="${error_msg}\n\t-Le commit local a échoué."
  fi

  if [ -z "${error_msg}" ]; then
    return 0
  else
    echo -e "Erreur send_commit() : ${error_msg}" >&2
    return 1
  fi
}

# -- MAIN --

nb_cycle=0
sleep_limit=$((HOUR_LIMIT * 3600))
while true; do
  ((nb_cycle++))
  echo ""
  echo "$(date '+%Y-%m/%d %H:%M:%S') -- CYCLE ${nb_cycle} --"
  LAST_PUSH_DATE="$(get_last_commit_date)"
  #Pour tester ave le format renvoyé par get_last_commit_date(), sans call API :
  #LAST_PUSH_DATE="2025-12-16T19:43:19Z"

  echo "Dernier commit public : ${LAST_PUSH_DATE}"

  #Date API vide
  if [ -z "${LAST_PUSH_DATE}" ]; then
    echo "Aucun commit public trouvé" >&2
    echo "Création du commit, nouvelle tentative dans ${HOUR_LIMIT}h"
    send_commit
    sleep "${sleep_limit}"
    continue
  fi

  # Date API non conforme
  if ! last_commit_ts=$(date -d "${LAST_PUSH_DATE}" +%s 2>/dev/null); then
    echo "Date invalide dans last_push_date : ${LAST_PUSH_DATE}" >&2
    echo "Envoi du commit par sécurité, nouvelle tentative dans ${HOUR_LIMIT}h" >&2
    send_commit
    sleep "${sleep_limit}"
    continue
  fi

  now_ts=$(date +%s)
  elapsed=$((now_ts - last_commit_ts))

  # Le dernier commit est plus récent que ${HOUR_LIMIT} heures, on se rendord pour atteindre >=${HOUR_LIMIT}
  if [ "${elapsed}" -lt "${sleep_limit}" ]; then
    remaining=$((sleep_limit - elapsed))
    echo "Dernier commit il y a $((elapsed / 3600))h, pas de commit à envoyer, attente $((remaining / 3600))h"
    sleep "${remaining}"
  else # Le dernier commit est plus ancien ou égal à ${HOUR_LIMIT}
    echo "Dernier commit >= ${HOUR_LIMIT} heures, envoi d'un nouveau commit."
    send_commit
    echo "nouveau cycle prévu dans ${HOUR_LIMIT} heures"
    sleep "${sleep_limit}"
  fi
done

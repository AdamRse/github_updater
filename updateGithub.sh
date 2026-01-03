#!/bin/bash

# SYSTEMD
# Nom du service : update-github.service
# Pour modifier $hour_limit, il faut redémarrer les service pour être pris en compte :
# sudo systemctl restart update-github.service
#
# Logs : journalctl -u update-github.service -f

USERNAME="AdamRse"
API_URL="https://api.github.com/users/$USERNAME/events/public"
REPO_PATH="/home/adam/dev/projets/NOTES-DE-COURS"

hour_limit=23
sleep_limit=$((hour_limit * 3600))

fichier_citations="/home/adam/.config/script/citations.txt"
fichier_sortie="/home/adam/dev/projets/NOTES-DE-COURS/citation_du_jour"

# Fonction pour obtenir une citation aléatoire
obtenir_citation_aleatoire() {
    [ -z $1 ] && echo "obtenir_citation_aleatoire() ERREUR : passer un chemin de fichier" >&2 && exit 1

    local fichier_citations_loc=$1
    local id=$(date +%s%N | md5sum | head -c20)

    # Vérifier si le fichier existe
    if [ ! -f "$fichier_citations_loc" ]; then
        echo "ERREUR: $id" >&2
        echo "Erreur : Le fichier $fichier_citations_loc n'existe pas" >&2
        return 1
    fi

    # Compter le nombre de citations
    local nombre_citations=$(grep -c "\*\*/" "$fichier_citations_loc")

    # Générer un nombre aléatoire entre 1 et le nombre de citations
    local index_aleatoire=$((RANDOM % nombre_citations + 1))

    # Extraire la citation choisie
    local citation=$(awk -v num="$index_aleatoire" 'BEGIN{RS="**/"} NR==num {print}' "$fichier_citations_loc")

    # Nettoyer la citation
    citation=$(echo "$citation" | tr -d '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Retourner la citation avec l'ID
    echo "$citation

/$id/"
}
get_last_commit_date() {
  curl -s "$API_URL" \
    | jq -r '
      .[]
      | select(.type == "PushEvent")
      | .created_at
      | select(. != null)
      ' \
    | head -n 1
}
send_commit() {
  cd "$REPO_PATH"
  if git pull \
    && obtenir_citation_aleatoire "$fichier_citations" > "$fichier_sortie" \
    && git add . && git commit -m "$(date +%s%N | md5sum | head -c5)" \
    && git push; then
    echo "changement de citation effectué avec succès !"
    return 0;
  else
    echo "Erreur lord de l'envoi du commit de citations, arrêt du programme." >&2
    echo "$(date '+%d/%m/%Y %H:%M:%S') Erreur lord de l'envoi du commit de citations, arrêt du programme." > "/home/adam/ERREUR_GITHUB_CITATIONS_AUTO"
    exit 1
  fi
}

nb_cycle=0
while true; do
  ((nb_cycle++))
  echo ""
  echo "$(date '+%Y-%m/%d %H:%M:%S') -- CYCLE ${nb_cycle} --"
  LAST_PUSH_DATE="$(get_last_commit_date)"
  #Pour tester ave le format renvoyé par get_last_commit_date(), sans call API :
  #LAST_PUSH_DATE="2025-12-16T19:43:19Z"

  echo "Dernier commit public : $LAST_PUSH_DATE"

  #Date API vide
  if [ -z "$LAST_PUSH_DATE" ]; then
    echo "Aucun commit public trouvé" >&2
    echo "Envoi du commit par sécurité, nouvelle tentative dans ${hour_limit}h" >&2
    send_commit
    sleep "$sleep_limit"
    continue
  fi

  # Date API non conforme
  if ! last_commit_ts=$(date -d "$LAST_PUSH_DATE" +%s 2>/dev/null); then
    echo "Date invalide dans last_push_date : $LAST_PUSH_DATE" >&2
    echo "Envoi du commit par sécurité, nouvelle tentative dans ${hour_limit}h" >&2
    send_commit
    sleep "$sleep_limit"
    continue
  fi

  now_ts=$(date +%s)
  elapsed=$((now_ts - last_commit_ts))

  # Le dernier commit est plus récent que ${hour_limit} heures, on se rendord pour atteindre >=${hour_limit}
  if [ "$elapsed" -lt "$sleep_limit" ]; then
    remaining=$((sleep_limit - elapsed))
    echo "Dernier commit il y a $((elapsed / 3600))h, pas de commit à envoyer, attente $((remaining / 3600))h"
    sleep "$remaining"
  else # Le dernier commit est plus ancien ou égal à ${hour_limit}
    echo "Dernier commit >= ${hour_limit} heures, envoi d'un nouveau commit."
    send_commit
    echo "nouveau cycle prévu dans ${hour_limit} heures"
    sleep "$sleep_limit"
  fi
done

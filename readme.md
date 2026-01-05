# Script de mise à jour automatique GitHub

Script Bash automatisant les commits sur un dépôt GitHub selon un cycle temporel défini. Si aucun commit public n'a été effectué pendant une durée spécifiée, le script génère automatiquement un commit avec une citation aléatoire.

## Fonctionnement

Le script surveille l'activité de commit public via l'API GitHub. Si aucun commit n'a été envoyé pendant la période définie (par exemple 23 heures), il :
1. Récupère une citation aléatoire depuis un fichier source
2. Met à jour un fichier dans le dépôt
3. Crée et envoie un commit automatiquement
4. Se met en veille jusqu'au prochain cycle

## Prérequis

**Système d'exploitation :** Linux uniquement

**Paquets requis :**
- `curl` - Pour les appels API
- `jq` - Pour parser le JSON
- `git` - Pour les opérations Git

Installation sur Debian/Ubuntu :
```bash
sudo apt install curl jq git
```

## Installation

### 1. Préparer les fichiers

Clonez ou téléchargez le script dans un répertoire de votre choix :
```bash
mkdir -p ~/.config/script
cd ~/.config/script
# Placez updateGithub.sh ici
chmod +x updateGithub.sh
```

### 2. Créer le fichier de citations

Créez un fichier `citations.txt` avec vos citations au format :
```
Citation 1 **/
Citation 2 **/
Citation 3 **/
```

Chaque citation doit se terminer par `**/`

### 3. Configuration du fichier .env

Créez un fichier `.env` dans le même répertoire que le script :

```bash
USERNAME="VotreUsername"
API_URL="https://api.github.com/users/${USERNAME}/events/public"
REPO_PATH="/chemin/vers/votre/repo"
HOUR_LIMIT=23
QUOTES_FILE="/chemin/vers/citations.txt"
QUOTE_OUTPUT_FILE="/chemin/vers/votre/repo/citation_du_jour"
```

**Variables :**
- `USERNAME` : Votre nom d'utilisateur GitHub
- `REPO_PATH` : Chemin absolu vers le dépôt Git local
- `HOUR_LIMIT` : Nombre d'heures entre chaque commit automatique
- `QUOTES_FILE` : Chemin vers le fichier de citations
- `QUOTE_OUTPUT_FILE` : Fichier à modifier dans le dépôt

### 4. Vérifier la configuration Git

Assurez-vous que votre dépôt Git est configuré avec les credentials appropriés :
```bash
cd /chemin/vers/votre/repo
git config user.name "Votre Nom"
git config user.email "votre@email.com"
```

## Configuration du service systemd

### 1. Créer le fichier service

Créez le fichier `/etc/systemd/system/update-github.service` :

```bash
sudo nano /etc/systemd/system/update-github.service
```

Contenu du fichier :
```ini
[Unit]
Description=Met à jour le repo github si aucun commit public n'a été effectué
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=votre_utilisateur
WorkingDirectory=/chemin/absolu/vers/votre/repo
ExecStart=/chemin/absolu/vers/updateGithub.sh

Restart=on-failure
RestartSec=3000
StartLimitBurst=3

# Logs
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**Remplacez :**
- `votre_utilisateur` : Votre nom d'utilisateur Linux
- `/chemin/absolu/vers/votre/repo` : Chemin absolu vers le dépôt Git
- `/chemin/absolu/vers/updateGithub.sh` : Chemin absolu vers le script

### 2. Activer et démarrer le service

```bash
# Recharger la configuration systemd
sudo systemctl daemon-reload

# Activer le service au démarrage
sudo systemctl enable update-github.service

# Démarrer le service
sudo systemctl start update-github.service
```

### 3. Vérifier le statut

```bash
# Vérifier que le service fonctionne
sudo systemctl status update-github.service

# Suivre les logs en temps réel
journalctl -u update-github.service -f

# Afficher les derniers logs
journalctl -u update-github.service -n 50
```

## Gestion du service

```bash
# Arrêter le service
sudo systemctl stop update-github.service

# Redémarrer le service (nécessaire après modification de HOUR_LIMIT)
sudo systemctl restart update-github.service

# Désactiver le service
sudo systemctl disable update-github.service

# Recharger après modification du fichier .service
sudo systemctl daemon-reload
sudo systemctl restart update-github.service
```

## Logs et débogage

Le script génère des logs détaillés via systemd :

```bash
# Logs en temps réel
journalctl -u update-github.service -f

# Logs depuis le démarrage
journalctl -u update-github.service --since today

# Logs des erreurs uniquement
journalctl -u update-github.service -p err
```

Chaque cycle affiche :
- La date et le numéro de cycle
- La date du dernier commit public
- Les actions effectuées (commit envoyé ou attente)
- Les temps d'attente

## Dépannage

**Le service ne démarre pas :**
- Vérifiez les permissions du script : `chmod +x updateGithub.sh`
- Vérifiez que tous les chemins dans `.env` sont corrects
- Consultez les logs : `journalctl -u update-github.service -n 50`

**Erreurs de commit :**
- Vérifiez la configuration Git du dépôt
- Assurez-vous que les credentials Git sont configurés
- Vérifiez les permissions d'écriture sur le dépôt

**Le service s'arrête :**
- Consultez les logs pour identifier l'erreur
- Vérifiez que les paquets requis sont installés
- Le service redémarrera automatiquement en cas d'échec (3 tentatives max)

## Licence

Ce script est fourni tel quel, sans garantie.
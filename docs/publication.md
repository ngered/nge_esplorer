# Publier une version pour les testeurs depuis Azure DevOps

La publication Android ne demande plus le poste Linux : un ordinateur prêté par Microsoft, dans Azure DevOps,
construit l'application, la signe et l'envoie aux testeurs Firebase App Distribution. La recette suivie est le
fichier `azure-pipelines.yml` à la racine du projet.

La mise en place se fait une seule fois (étapes 1 à 5). Ensuite, publier se résume à l'étape 6.

## 1. Vérifier que l'organisation a droit aux ordinateurs prêtés

Dans Azure DevOps : **Organization settings** (en bas à gauche) **> Pipelines > Parallel jobs**.

- Si la ligne **Microsoft-hosted** indique au moins 1 job (gratuit ou acheté) : rien à faire.
- Si elle indique 0 : demander l'accès gratuit par le formulaire <https://aka.ms/azpipelines-parallelism-request>
  (projet privé, 1 800 minutes par mois). La réponse arrive en général sous deux ou trois jours ouvrés. Si
  l'organisation est administrée par la DSI, c'est à elle de faire la demande ou d'acheter le job.

## 2. Choisir la clé de signature

Android n'installe une nouvelle version par-dessus l'ancienne que si les deux sont signées par la même clé.
Jusqu'ici, les versions étaient signées par la clé de débogage du poste Linux.

- **Recommandé : créer la clé définitive de l'application.** Les testeurs désinstallent une seule fois la version
  actuelle avant d'installer la première version publiée par Azure ; ensuite, plus rien à faire. C'est aussi la
  clé qui servira pour le Play Store. Sur un poste où Java est installé :

  ```
  keytool -genkeypair -v -keystore nge_esplorer.jks -keyalg RSA -keysize 2048 -validity 10000 -alias nge_esplorer
  ```

  L'outil demande un mot de passe (à noter) puis quelques renseignements (nom, organisation : NGE-ES…).
  **Conserver le fichier `nge_esplorer.jks` et son mot de passe en lieu sûr** (coffre de mots de passe, copie
  hors du poste) : sans eux, plus aucune mise à jour de l'application n'est possible.

- **Alternative : reprendre la clé de débogage du poste Linux**, pour éviter la désinstallation. Copier le fichier
  `~/.android/debug.keystore` du poste Linux et le renommer `nge_esplorer.jks` ; alias `androiddebugkey`, mots de
  passe `android`. Solution provisoire : cette clé n'est pas faite pour une application diffusée.

## 3. Créer l'accès à Firebase pour l'ordinateur prêté

L'ordinateur prêté ne peut pas faire `firebase login` : il utilise un compte de service.

1. Ouvrir <https://console.cloud.google.com>, choisir le projet Firebase de NgeEsPlorer (en haut de la page).
2. **IAM et administration > Comptes de service > Créer un compte de service** ; nom : `azure-publication`.
3. Rôle : **Administrateur Firebase App Distribution** (*Firebase App Distribution Admin*) ; terminer.
4. Ouvrir le compte créé, onglet **Clés > Ajouter une clé > Créer une clé > JSON** : un fichier se télécharge.
   Le renommer `firebase-distribution.json`. Il donne le droit de publier : ne pas le diffuser.

## 4. Déposer les fichiers et les réglages dans Azure DevOps

Dans le projet `nge_esplorer` : **Pipelines > Library**.

**Fichiers sécurisés** (onglet *Secure files* > *+ Secure file*) : déposer `nge_esplorer.jks` et
`firebase-distribution.json`, avec exactement ces noms.

**Groupe de variables** (onglet *Variable groups* > *+ Variable group*), nommé `publication-android` :

| Nom | Valeur | Secret (cadenas) |
|---|---|---|
| `FIREBASE_APP_ID` | ID de l'application Android, de la forme `1:123…:android:abc…` (console Firebase > Paramètres du projet > Général > Vos applications ; aussi dans le `.env` du poste Linux) | non |
| `FIREBASE_GROUPS` | `testeurs_ngeesplorer` | non |
| `KEY_ALIAS` | `nge_esplorer` (ou `androiddebugkey` pour la clé du poste Linux) | non |
| `KEYSTORE_PASSWORD` | mot de passe de `nge_esplorer.jks` | **oui** |
| `KEY_PASSWORD` | mot de passe de la clé (le même, sauf choix contraire) | **oui** |

Enregistrer (*Save*).

## 5. Créer le pipeline

**Pipelines > New pipeline > Azure Repos Git > nge_esplorer > Existing Azure Pipelines YAML file**, branche
`main`, chemin `/azure-pipelines.yml` ; *Continue*, puis dans le menu de *Run*, choisir **Save** (enregistrer sans
lancer). Le renommer au besoin (menu ⋮ > *Rename/move*) : « Publication Android ».

## 6. Publier une version

**Pipelines > Publication Android > Run pipeline** :

- **Notes de version** : texte vu par les testeurs ; vide, c'est le titre du dernier commit poussé sur Azure ;
- **Envoyer aux testeurs Firebase** : décoché, l'APK est seulement construit (pour essai) ;
- **Lancer les tests avant la construction** : décocher pour gagner quelques minutes, quand les tests viennent
  d'être passés sur le poste ;
- **Run**.

À la première exécution, Azure demande d'autoriser l'accès aux fichiers et au groupe de variables
(*This pipeline needs permission…* > **View > Permit**) : à faire une seule fois.

Compter une quinzaine de minutes la première fois ; ensuite, Flutter, les dépendances Dart et Gradle sont repris
du cache de l'exécution précédente. Le déroulé s'affiche étape par étape ;
une coche verte partout : la version est chez les testeurs. L'APK reste aussi téléchargeable depuis la page de
l'exécution (**Related > published**).

Le pipeline publie ce qui est sur la branche `main` d'Azure : pousser vers Azure avant de lancer.

## Numéros de version

Chaque publication prend un numéro de build croissant, tenu par Azure : 100, 101, 102… (affiché sur l'écran
d'accueil : `1.0.0+100`). Il n'y a plus de commit de numéro de version à faire. La partie `1.0.0` reste celle de
`pubspec.yaml`, à changer à la main pour une nouvelle version majeure.

Le script `build_apk_adb.sh` du poste Linux continue de fonctionner (installation par câble, publication
`DISTRIBUTE=1`) ; une fois la publication par Azure adoptée, ne plus publier par le poste Linux, pour ne pas
mélanger les clés de signature ni les numéros.

## En cas d'échec

Ouvrir l'étape en rouge pour lire le message. Les causes les plus courantes :

- *No hosted parallelism has been purchased or granted* : étape 1 ;
- *Could not find secure file* ou *variable group not found* : noms de l'étape 4 à vérifier, ou autorisation de
  l'étape 6 à donner ;
- *Keystore was tampered with, or password was incorrect* : `KEYSTORE_PASSWORD` ou `KEY_PASSWORD` ;
- échec de l'envoi Firebase (*permission denied*) : rôle du compte de service (étape 3) ou `FIREBASE_APP_ID`.

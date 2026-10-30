# description

Objet : application mobile android (apk) multi métiers (télécoms et élec)
technologie :
- flutter + dart
- application apk préféré au PWA (fonctionnement hors ligne, performances)

socle commun, SIG, gestion photos, formulaires pilotés
modules métiers indépendants et combinés : optique, parcours d'infras, immeubles, administratif (adresses), réseau électrique...

En pratique :
Application déployée via store ou téléchargement APK
Accès à l'application via jeton abonné.
Accès aux données/technicien via jeton abonné. 
Jetons utilisateurs intégrant l'accès à l'application et abonnement aux zones dédiés, révocables par controle d'administration via SAS azure.
Données abonnés geojson téléchargées par l'utilisateur via l'application depuis SAS azure
Données cryptées ne peuvent être lues que par l'application et jeton abonné.
Synchronisation à la demande.
Données abonnés = GEOSJON + fonds de plans pour travail en zone blanche sans perte de productivité.



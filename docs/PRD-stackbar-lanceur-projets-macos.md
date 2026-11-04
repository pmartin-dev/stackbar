# PRD : Stackbar, lanceur de projets dans la barre de menu macOS

**Statut** : cadrage validé par l'utilisateur.
**Source** : journal de cadrage `docs/grilling-journal-lanceur-projets-macos.md` (questions 1 à 32, décisions confirmées).

---

## 1. Contexte et problème

L'utilisateur possède plusieurs projets locaux, rangés dans un dossier `Projets/` (sous-dossiers `Perso/` et `Pro/`). Ces projets ne se lancent pas de la même façon : certains avec npm, d'autres avec docker compose, un Makefile, Maven ou Python. Pour lancer, suivre ou arrêter un projet, il faut aujourd'hui retrouver la bonne commande dans le bon dossier. Il n'existe aucune vue centralisée de ce qui tourne.

Stackbar doit offrir un point d'accès unique depuis la barre de menu macOS : voir les projets actifs, lancer ou arrêter un projet, et consulter ses logs.

## 2. Utilisateurs

- **Utilisateur initial** : le développeur à l'origine du projet, qui gère des projets locaux variés.
- **Autres utilisateurs** : l'app est open source. D'autres personnes l'installeront avec leurs propres projets. Chacune gère sa propre configuration.

## 3. Objectifs

- **O1** Lancer et arrêter un projet en un clic depuis la barre de menu.
- **O2** Voir d'un coup d'œil quels projets sont actifs.
- **O3** Configurer tous ses projets sans éditer de fichier à la main.
- **O4** Être certain qu'un projet arrêté ou en erreur est signalé.

## 4. Non-objectifs (hors version 1)

- Détecter les processus lancés hors de l'app (terminal, IDE).
- Scanner automatiquement le dossier `Projets/` pour proposer des projets.
- Conserver l'historique des logs entre les sessions.
- Ouvrir automatiquement le navigateur quand une URL est détectée.
- Autoriser plusieurs instances d'un même projet.
- Gérer des variables d'environnement ou un PATH propres à chaque projet.

## 5. Exigences

### 5.1 Présence et interface

- **R1** L'app vit dans la barre de menu macOS. Elle n'apparaît pas dans le Dock.
- **R2** L'icône de la barre de menu est fixe. Elle n'indique pas l'activité des projets.
- **R3** L'interface est en anglais uniquement.
- **R4** Un clic sur l'icône affiche un menu avec deux sections : **Running** (projets actifs) et **Stopped** (projets configurés non actifs).
- **R5** Une fenêtre Préférences est accessible depuis le menu.

### 5.2 Configuration des projets

- **R6** Chaque projet possède : un nom affiché, un chemin de dossier, une commande de lancement et une commande d'arrêt optionnelle.
- **R7** Le nom affiché est saisi dans les Préférences. Il est pré-rempli avec le nom du dossier et reste modifiable.
- **R8** Une seule commande de lancement par projet, en texte libre. Elle peut enchaîner plusieurs étapes.
- **R9** Les projets peuvent se trouver à n'importe quel emplacement. Le chemin est saisi pour chaque projet. Il n'y a pas de scan automatique.
- **R10** À la saisie, le dossier doit exister et la commande ne doit pas être vide. La commande n'est pas exécutée à la saisie.
- **R11** Un projet peut être modifié et supprimé depuis les Préférences.
- **R12** La configuration est propre à chaque utilisateur et stockée localement, comme pour toute app macOS. Elle n'est pas incluse dans le dépôt de code.

### 5.3 Lancement

- **R13** Les commandes s'exécutent dans le dossier du projet, avec le même environnement qu'un terminal ouvert par l'utilisateur (PATH et configuration de son shell de connexion).
- **R14** Un projet ne peut avoir qu'une seule instance active. Quand il est actif, l'action « Lancer » est grisée, avec une explication au survol. « Relancer » reste disponible.
- **R15** Un projet arrêté apparaît dans la section **Stopped** avec une action « Lancer ».
- **R16** L'app ne lance jamais un projet automatiquement sans action de l'utilisateur.
- **R17** Une option « lancer l'app à l'ouverture de session » est disponible dans les Préférences. Elle est désactivée par défaut.

### 5.4 Arrêt, fermeture et suppression

- **R18** « Arrêter » arrête le processus lancé et tous ses processus enfants. Si une commande d'arrêt est définie, elle est exécutée en plus.
- **R19** « Relancer » arrête puis relance le projet.
- **R20** À la fermeture de l'app : si au moins un projet est actif, un message de confirmation est affiché, puis tous les projets actifs sont arrêtés. Sans projet actif, l'app se ferme directement.
- **R21** Supprimer un projet actif demande une confirmation, puis arrête le projet, puis le retire de la configuration.

### 5.5 Actions sur un projet actif

- **R22** Un projet actif propose cinq actions : Arrêter, Relancer, Voir les logs, Ouvrir le dossier, Ouvrir l'URL.
- **R23** « Ouvrir le dossier » ouvre le dossier du projet dans le Finder.
- **R24** « Voir les logs » ouvre une fenêtre dans l'app qui affiche la sortie de la session en cours.
- **R25** Après l'arrêt d'un projet, ses logs restent consultables. Ils sont effacés au prochain lancement de ce projet.
- **R26** L'URL d'un projet est détectée automatiquement depuis la sortie de sa commande.
- **R27** Si aucune URL n'est détectée, « Ouvrir l'URL » reste affichée mais désactivée.
- **R28** Le navigateur ne s'ouvre que sur action explicite de l'utilisateur (« Ouvrir l'URL »), jamais automatiquement.

### 5.6 Statut et notifications

- **R29** Un projet qui s'arrête, normalement ou en erreur, reste visible avec un statut qui indique l'arrêt ou l'erreur.
- **R30** Une notification macOS est envoyée à chaque arrêt, normal ou en erreur.
- **R31** Deux réglages dans les Préférences contrôlent les notifications : « notifier à l'arrêt normal » et « notifier en cas d'erreur ». Ils sont tous deux activés par défaut.

## 6. Décisions confirmées et justifications

| # | Décision | Justification (si donnée par l'utilisateur) |
|---|---|---|
| D1 | La section « Running » ne liste que les projets lancés depuis l'app. Pas de détection hors app. | Choix de l'utilisateur, parmi trois options proposées. |
| D2 | Ajout des projets manuel uniquement. Pas de scan de `Projets/`. | Choix de l'utilisateur. |
| D3 | Un projet = une commande de lancement en texte libre. | Choix de l'utilisateur. |
| D4 | La configuration se saisit uniquement dans une fenêtre Préférences. | Choix de l'utilisateur. |
| D5 | Fermeture de l'app : confirmation si un projet est actif, puis arrêt de tous les projets. | Choix de l'utilisateur. |
| D6 | Cinq actions sur un projet actif : Arrêter, Relancer, Voir les logs, Ouvrir le dossier, Ouvrir l'URL. | Choix de l'utilisateur. |
| D7 | URL détectée depuis la sortie de la commande. Action désactivée si absente. | Choix de l'utilisateur. |
| D8 | Commandes exécutées avec l'environnement du shell de connexion de l'utilisateur. | Choix de l'utilisateur. |
| D9 | Logs dans une fenêtre de l'app, session en cours, consultables après arrêt jusqu'au prochain lancement. | Choix de l'utilisateur. |
| D10 | Lancement à l'ouverture de session : option désactivée par défaut. | Choix de l'utilisateur. |
| D11 | Statut visible à chaque arrêt, avec notification à chaque arrêt. Deux réglages séparés, activés par défaut. | Choix de l'utilisateur. |
| D12 | « Arrêter » couvre le processus, ses enfants et une commande d'arrêt optionnelle par projet. | Choix de l'utilisateur. |
| D13 | Projet open source sous licence MIT, destiné à d'autres utilisateurs. | « open source sur mon github » ; « ce projet n'est pas que pour moi ». |
| D14 | Configuration propre à chaque utilisateur, stockée localement comme pour toute app macOS. | « la config de chaque personne doit etre stockée comme n'importe quelle app mac ». |
| D15 | Interface en anglais uniquement. | Choix de l'utilisateur. |
| D16 | Version minimale de macOS : 26. | Choix de l'utilisateur. |
| D17 | Icône de la barre de menu fixe, sans indicateur d'activité. | Choix de l'utilisateur. |
| D18 | Nom affiché saisi, pré-rempli avec le nom du dossier. | Choix de l'utilisateur. |
| D19 | Une seule instance par projet. « Lancer » grisé avec explication au survol quand le projet est actif. | Réponse libre de l'utilisateur. |
| D20 | Menu en deux sections : « Running » et « Stopped ». | Choix de l'utilisateur. |
| D21 | Validation à la saisie : dossier existant, commande non vide. | Choix de l'utilisateur. |
| D22 | Pas d'ouverture automatique du navigateur. | Choix de l'utilisateur. |
| D23 | Nom de l'app : **Stackbar**. | Choix de l'utilisateur parmi des propositions. |
| D24 | Pas d'icône dans le Dock. Barre de menu uniquement. | Choix de l'utilisateur. |
| D25 | Suppression d'un projet actif : confirmation, arrêt, puis retrait. | Choix de l'utilisateur. |
| D26 | Hors v1 : les six éléments listés au §4. | Choix de l'utilisateur. |
| D27 | Critères de réussite de la v1 : voir §10. | Choix de l'utilisateur. |

## 7. Hypothèses confirmées

- La machine de l'utilisateur tourne sous macOS 27.2 (vérifié sur la machine).
- Les projets de référence se trouvent dans `Projets/Perso/` et `Projets/Pro/`. Ils lancent leurs services par des moyens variés (npm, docker compose, Makefile, Maven, Python).

## 8. Contraintes

- **Plateforme** : macOS 26 minimum.
- **Langue** : anglais uniquement.
- **Distribution** : code public sur GitHub, sous licence MIT.
- **Confidentialité de la configuration** : la configuration de chaque utilisateur reste locale et ne figure pas dans le dépôt.
- **Environnement d'exécution** : les commandes doivent fonctionner comme dans un terminal ouvert par l'utilisateur.

## 9. Questions ouvertes

- L'ordre d'exécution entre l'arrêt du processus et la commande d'arrêt optionnelle n'est pas tranché.
- Quelles actions sont disponibles dans la section « Stopped », au-delà de « Lancer » (par exemple, consulter les logs d'un projet arrêté) ? Non tranché.
- Que se passe-t-il si « Arrêter » ou « Relancer » échoue ? Non tranché.
- La disponibilité du nom « Stackbar » (dépôt, marque) n'est pas vérifiée.

## 10. Critères d'acceptation

- [ ] L'icône apparaît dans la barre de menu et l'app n'apparaît pas dans le Dock.
- [ ] Un clic sur l'icône affiche les sections « Running » et « Stopped ».
- [ ] Un projet se crée dans les Préférences avec un chemin et une commande. Le nom est pré-rempli avec le nom du dossier. Un dossier inexistant et une commande vide sont refusés.
- [ ] Lancer un projet arrêté le fait passer dans « Running ». Ses commandes s'exécutent dans son dossier avec l'environnement d'un terminal de l'utilisateur.
- [ ] « Lancer » est grisé, avec une explication au survol, pour un projet actif.
- [ ] « Arrêter » arrête le processus et ses enfants. La commande d'arrêt est exécutée si elle est définie.
- [ ] Quitter l'app avec un projet actif affiche une confirmation, puis arrête tous les projets. Sans projet actif, pas de confirmation.
- [ ] Supprimer un projet actif affiche une confirmation, puis arrête le projet, puis le retire.
- [ ] « Voir les logs » affiche la sortie de la session en cours. Après arrêt, les logs restent consultables. Ils sont effacés au prochain lancement.
- [ ] L'URL est détectée depuis la sortie de la commande. « Ouvrir l'URL » est désactivée si aucune URL n'est détectée. Le navigateur ne s'ouvre que sur action de l'utilisateur.
- [ ] « Ouvrir le dossier » ouvre le dossier du projet dans le Finder.
- [ ] Un projet arrêté normalement ou en erreur reste visible avec un statut qui l'indique.
- [ ] Une notification est envoyée à chaque arrêt, selon les deux réglages (arrêt normal, erreur), activés par défaut.
- [ ] L'option « lancer à l'ouverture de session » est désactivée par défaut. Aucun projet ne se relance automatiquement.
- [ ] La configuration n'est pas incluse dans le dépôt de code.
- [ ] **Succès v1** : on lance et arrête un projet en un clic depuis la barre de menu ; tous les projets se configurent sans éditer de fichier ; un projet arrêté ou en erreur est toujours signalé.

# Architecture technique et choix technologiques — Stackbar

**Statut :** architecture consolidée à partir des choix confirmés et des recommandations retenues pour les points ouverts. Les contrôles d'implémentation et de publication sont indiqués au §8.

**Sources :** [`PRD-stackbar-lanceur-projets-macos.md`](PRD-stackbar-lanceur-projets-macos.md) et [`grilling-journal-technical-design-stackbar.md`](grilling-journal-technical-design-stackbar.md).

## 1. Objectif et périmètre

Stackbar est une application macOS native qui permet de configurer, lancer, suivre et arrêter des projets locaux depuis la barre de menu. Le présent document définit la base d'architecture et les choix techniques nécessaires au périmètre inclus dans le PRD. Les exclusions listées dans le PRD restent hors périmètre.

La configuration des projets reste locale à chaque compte macOS et ne doit pas être versionnée avec le code.

## 2. Architecture générale

### Application et interface

- **Swift 6**, avec vérifications strictes de concurrence.
- Application native **SwiftUI**, avec **AppKit** pour les intégrations système nécessaires.
- Projet Xcode `.xcodeproj`, dépendances gérées par **Swift Package Manager**.
- Un target d'application organisé par features TCA et un target de tests séparé.
- **The Composable Architecture (TCA)** pilote l'état et les effets. `AppFeature` compose les features Projets, Préférences et Logs ; les services système sont injectés via les dépendances TCA.
- TCA est la seule dépendance directe : plage à partir de `1.26.2` et avant `2.0.0`, avec `Package.resolved` commité. Ses dépendances transitives sont acceptées.
- Cible minimale : **macOS 26.0**.

### Scènes macOS

- `MenuBarExtra` SwiftUI en style menu pour l'icône fixe et les sections **Running** et **Stopped**.
- Scène SwiftUI `Settings` pour les Préférences.
- Fenêtre de logs par projet, identifiée par son UUID stable.
- `LSUIElement = true` pour ne pas afficher Stackbar dans le Dock ni le sélecteur d'applications.

## 3. Données et persistance

### Configuration d'un projet

Le modèle persistant `Project` contient un UUID stable, le nom affiché, le chemin du dossier, la commande de lancement et, facultativement, la commande d'arrêt. Le modèle d'exécution `ProjectRuntime` est distinct et reste en mémoire ; ni état de processus ni logs ne sont enregistrés dans le fichier de configuration. Deux projets ne peuvent pas référencer le même dossier canonique. Les modifications d'un projet en cours ne s'appliquent qu'au prochain lancement.

### Stockage et validation

- Définitions de projets en `projects.json` sous `~/Library/Application Support/Stackbar/`, avec accès limité au compte utilisateur.
- Document avec version de schéma et liste de projets ; migrations séquentielles pour les schémas connus.
- `ProjectRepository` actor, injecté dans TCA, responsable du chargement, de la validation, des migrations et de la sauvegarde.
- Écritures atomiques : une nouvelle configuration ne remplace la précédente qu'après écriture réussie.
- Fichier illisible ou version inconnue : préserver le fichier, afficher une erreur explicite et ne pas réinitialiser automatiquement.
- Choisir le dossier avec `NSOpenPanel`; refuser un dossier absent ou une commande vide à l'enregistrement, puis revalider le dossier au lancement.
- Préférences simples, notamment les deux réglages de notification activés par défaut, dans `UserDefaults` via TCA.

## 4. Exécution et cycle de vie des processus

`ProjectProcessManager` actor possède les processus actifs, indexés par UUID, et sérialise les actions démarrer/arrêter/relancer. Un projet ne peut avoir qu'une seule instance active. Les événements de cycle de vie arrivent aux reducers via `AsyncStream`; les objets `Process` ne résident pas dans l'état TCA.

Les commandes sont lancées avec `Foundation.Process`, dans le dossier du projet. Stackbar lit le shell configuré pour le compte via `getpwuid`, prend en charge **zsh** et **bash**, et signale explicitement tout autre shell. zsh est lancé avec `-ilc`, bash avec `--login -i -c`; le texte de commande est transmis comme argument unique de `-c` et le dossier via `Process.currentDirectoryURL`.

Les commandes n'ont pas de terminal ni d'entrée interactive. stdout et stderr sont fusionnés et drainés de manière asynchrone. L'app ne lance aucun projet automatiquement : l'option d'ouverture de session ne lance que Stackbar.

Pour arrêter un projet, la commande d'arrêt optionnelle est exécutée d'abord, puis Stackbar demande la terminaison du processus suivi et de ses sous-processus. Une relance attend la fin de l'ancienne session avant de démarrer la suivante. L'app ne doit jamais afficher un arrêt réussi tant que la terminaison n'est pas confirmée.

La commande d'arrêt, lancée dans le même shell et dossier, a un délai maximal de 30 secondes. Si elle échoue ou expire, Stackbar enregistre l'erreur mais tente quand même de terminer le processus suivi. Après `Process.terminate()`, Stackbar attend jusqu'à 10 secondes. Si le processus est toujours actif, elle conserve son état d'erreur et son suivi ; elle ne prétend pas qu'il est arrêté, n'en démarre pas une seconde instance et n'envoie pas de `SIGKILL` automatique.

Une relance ne démarre qu'après la terminaison confirmée de l'ancienne session et la réussite de la séquence d'arrêt. Si une suppression ou une fermeture rencontre une erreur dans la séquence d'arrêt, Stackbar reste ouverte et conserve le projet dans sa configuration pour permettre une nouvelle tentative. À la fermeture, les arrêts sont lancés en parallèle après confirmation, puis l'app attend tous les résultats. Ces choix privilégient l'absence de processus orphelins invisibles plutôt qu'une fermeture forcée.

Une sortie inattendue avec code 0 est classée comme normale ; un code non nul, un signal inattendu ou l'échec de la commande d'arrêt est classé comme une erreur. Un arrêt demandé par l'utilisateur est normal si la séquence aboutit. Envoyer au plus une notification par session, selon la catégorie et le réglage choisi. Si la suppression d'un projet ne peut terminer son processus, conserver l'entrée de configuration.

## 5. Logs et détection d'URL

`LogStore` actor conserve les données brutes hors de l'état TCA. Les logs sont en mémoire uniquement, conservés après arrêt jusqu'au prochain lancement du projet, et supprimés à la fermeture de l'app.

- Tampon maximal de **10 MiB UTF-8 par projet** ; éviction des lignes les plus anciennes et indicateur visible de troncature.
- Décodage UTF-8 incrémental pour les chunks de pipe ; les séquences ANSI sont retirées avant affichage et analyse.
- La détection utilise Regex Foundation et `URLComponents`, retient la première URL HTTP(S) locale valide et n'ouvre le navigateur que sur action explicite. Sont considérés locaux : `localhost`, les adresses loopback, les adresses assignées à cette machine et `0.0.0.0` (normalisé en `localhost`) ; les hôtes publics ou privés non assignés à la machine sont ignorés.
- L'ouverture du dossier ou de l'URL passe par `NSWorkspace.shared.open`.
- Dans **Stopped**, proposer « Lancer » et, si la session précédente a encore des logs, « Voir les logs ». Ne pas proposer l'URL d'une session arrêtée.
- À la suppression réussie d'un projet, fermer sa fenêtre de logs et libérer son tampon. Si l'arrêt échoue, garder le projet et ses logs.

Les chemins sont conservés comme chemins absolus normalisés. Le même dossier canonique ne peut pas être enregistré deux fois ; il faut aussi revalider que le dossier existe au lancement.

## 6. Intégrations macOS

- **Ouverture de session :** `ServiceManagement.SMAppService.mainApp`. Cela ouvre Stackbar uniquement, jamais les projets.
- **Notifications :** `UserNotifications.UNUserNotificationCenter`. Demander l'autorisation avant le premier lancement de projet sans bloquer celui-ci si l'autorisation est refusée.
- **Préférences de notification :** deux réglages indépendants (arrêt normal et erreur), activés par défaut.
- Si l'autorisation de notifications est refusée, afficher l'état et les instructions pour l'activer dans Réglages Système ; ne pas répéter la demande et ne pas bloquer les projets.
- **Dossiers et URL :** `NSWorkspace.shared.open`.
- **App Sandbox :** désactivé pour permettre l'exécution des commandes et l'accès aux dossiers choisis ; les permissions macOS/TCC et POSIX continuent de s'appliquer.
- Un `AppTerminationCoordinator` AppKit centralise Quit, Cmd-Q et les demandes de terminaison système : confirmation, arrêt des projets, puis réponse à macOS. Si l'utilisateur annule ou si l'arrêt échoue, annuler la terminaison et garder l'icône disponible.
- `MenuBarExtra` reste l'hôte retenu. Le retrait de l'icône doit passer par le même cycle de terminaison ; si macOS contourne ce flux, utiliser `NSStatusItem` avec une vue SwiftUI pour garantir l'arrêt propre.
- L'état du login item vient de `SMAppService.mainApp.status`. Signer le bundle en ad hoc (sans Developer ID ni notarisation) ; afficher les erreurs d'enregistrement et ne jamais montrer un état activé si macOS ne l'a pas confirmé.

## 7. Tests, build et distribution

- **Tests :** Swift Testing et TCA `TestStore` pour modèles, reducers et services ; XCTest/XCUITest uniquement pour les parcours UI nécessitant les vraies fenêtres macOS.
- **Build :** Xcode complet avec Swift tools 6.4 ou plus récent, requis par la version choisie de TCA.
- **Architecture binaire :** Universal `arm64` + `x86_64`.
- **CI/release :** GitHub Actions sur tag pour build, tests et génération d'un DMG ; publication GitHub validée manuellement.
- Les pull requests exécutent aussi build et tests. La CI épingle un Xcode complet compatible Swift tools 6.4.
- **Packaging :** `hdiutil`, sans dépendance de packaging tierce ; code source MIT et DMG versionné publiés sur GitHub.
- **Signature :** signature ad hoc du bundle, sans compte Developer ID ni notarisation. Cela ne supprime pas les avertissements Gatekeeper ; les releases doivent inclure des instructions d'installation macOS.
- Inclure les notices de licence requises par TCA et ses dépendances transitives.
- Pas d'auto-updater ; GitHub Releases est le canal de mise à jour.

## 8. Décisions finales et contrôles de release

Les choix techniques sont arrêtés comme suit :

1. Une commande d'arrêt expire au bout de 30 secondes ; Stackbar tente ensuite d'arrêter le processus suivi. Après 10 secondes sans confirmation d'arrêt, elle signale l'échec, garde le processus suivi et refuse relance, suppression ou fermeture silencieuses.
2. Les erreurs d'arrêt/relance sont visibles. Une relance ne crée jamais une deuxième instance si l'arrêt de la première n'est pas confirmé.
3. La section **Stopped** propose « Lancer » et « Voir les logs » si une sortie précédente est encore conservée ; pas d'URL ouvrable pour un projet arrêté.
4. Les URL reconnues sont celles de la machine locale (loopback, `localhost`, adresses affectées à ses interfaces) ; `0.0.0.0` devient `localhost`.
5. Le nom produit reste **Stackbar**. Des dépôts `stackbar` existent sous d'autres propriétaires, par exemple [Sebas1337/stackbar](https://github.com/Sebas1337/stackbar) ; cela n'empêche pas d'utiliser le même slug sous un autre compte. Choisir `stackbar` sous le propriétaire du projet, ou `stackbar-macos` s'il y est déjà pris. Une vérification de marque reste une condition de publication, pas un choix d'architecture.
6. L'identifiant de bundle suit `io.github.<proprietaire-normalise>.stackbar`, fixé avant le premier build public et conservé ensuite.

Avant release, les tests d'acceptation doivent confirmer : arrêt de processus enfants, interception de la fermeture/retrait de l'extra, commandes zsh/bash sans TTY, tooltip de « Lancer » désactivé, et enregistrement du login item avec le bundle ad hoc réellement distribué.

L'environnement courant n'a pas de Xcode complet sélectionné (`xcodebuild` indisponible) ; le build n'a pas été validé ici. Les tests de release devront tourner sur un runner macOS doté d'un Xcode compatible Swift tools 6.4.

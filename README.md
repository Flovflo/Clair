# Clair

Application native macOS 14+ en SwiftUI pour comprendre le stockage et préparer un nettoyage local et réversible.

## Installation

**macOS 14 ou ultérieur · Apple Silicon et Intel · Interface en français**

Télécharger le DMG ou le ZIP depuis les [releases officielles](https://github.com/Flovflo/Clair/releases).
Ouvrir le DMG et glisser **Clair** vers **Applications**, puis ouvrir l’application.
Le ZIP permet une installation manuelle. Les sommes SHA-256 accompagnent les fichiers.
Consulter les notes de la release pour les vérifications de signature et de notarisation.

## Utilisation

Ouvrir **Clair** depuis Applications. Au démarrage, un assistant vérifie l’accès au disque. **Ouvrir les réglages d’accès** mène directement au bon panneau macOS : activer l’interrupteur **Clair**, puis revenir et choisir **Relancer Clair**. Une aide dépliable indique le chemin exact de l’app si elle doit être ajoutée avec +. Après relance, l’accès est revérifié et l’analyse demandée démarre automatiquement. Le dernier rapport reste consultable avec **Consulter le dernier rapport**.

Cette autorisation est propre à Clair, indépendante de celle de Codex ou du Terminal. L’app n’active jamais l’interrupteur elle-même et ne propose aucun sélecteur de dossier. Le même assistant est accessible depuis la barre latérale. La préparation et l’exécution d’un nettoyage revérifient aussi l’accès avant de lire les cibles.

- **Analyser tout le Mac** mesure tous les fichiers accessibles du disque de démarrage, y compris les dossiers cachés. Aucun dossier à sélectionner. L’application vérifie d’abord l’accès à une ressource protégée ; si ce contrôle échoue, elle affiche l’assistant et attend l’autorisation avant de parcourir le disque.
- **Rapport** nomme les principaux responsables : projets et leurs `.artifacts`/`.worktrees`, applications, modèles IA, simulateurs, caches et données système. Il propose une piste de tri pour chaque ligne. Le rapport s’exporte en Markdown avec les chemins, les tailles, la date et la couverture.
- Les catégories du disque (vidéos, images, documents, code, dépendances, modèles, caches, applications, système…) apparaissent pendant le scan avec leurs tailles. Chaque fichier est classé une seule fois. La catégorie ne vaut jamais autorisation de suppression.
- **Fichiers** recherche dans tous les chemins indexés, sans plafond de 300 fichiers. Pagination par 100, filtres de taille et de dernière modification, tri par taille/nom/date. Cliquer une catégorie filtre cette vue.
- **Dossiers lourds** montre les dossiers de tout le scan. Ils sont imbriqués : ne pas additionner leurs tailles. **Explorer** descend dans leur contenu, y compris les petits fichiers et fichiers cachés.
- **Pistes de tri** détaille pourquoi chaque gros emplacement mérite une vérification. Le détail indique le chemin, la taille et la date ; les candidats autorisés peuvent être ajoutés à la sélection, puis revérifiés et déplacés dans la Corbeille après confirmation.
- L’inventaire SQLite est local, dans `~/Library/Application Support/Clair/inventory.sqlite`. Il contient des chemins et métadonnées, pas le contenu des fichiers. Il est restauré à la prochaine ouverture ; une annulation préserve la précédente analyse terminée. Cet index est exclu du scan lui-même. Les liens physiques restent consultables sous chaque chemin, avec les blocs partagés comptés une seule fois.
- Aucun vidage automatique de la Corbeille. Un déplacement dans la Corbeille ne libère pas immédiatement l’espace.

## Nettoyage autorisé

DerivedData, caches Xcode, support d’appareils, archives Xcode, dépôts Hugging Face, modèles LM Studio, bibliothèques Ollama et MTPLX, caches d’applications et installateurs `.dmg`/`.pkg` de Téléchargements. Les bibliothèques Ollama et MTPLX sont proposées entières avec avertissement explicite.

Depuis l’explorateur : `.build` Swift et `node_modules` avec leur manifeste adjacent, ainsi que les rapports `.xcresult` sous les emplacements de projets autorisés. Un projet entier, un worktree ou un dossier `.artifacts` entier n’est jamais considéré jetable.

Seuls les caches Xcode régénérables inactifs depuis sept jours entrent dans la sélection rapide. Les modèles, archives et autres caches nécessitent un choix explicite. Documents, photos, sources, données système et simulateurs restent consultables ; leur gestion se fait via le Finder ou l’application propriétaire.

## Limites honnêtes

L’analyse ne garantit pas l’accès à chaque fichier, même avec l’accès complet au disque : macOS protège certains emplacements. Les erreurs sont affichées. Les volumes montés et les instantanés APFS sont exclus de l’analyse globale. Les tailles sont des estimations de blocs alloués : compression, clones APFS et liens physiques peuvent faire différer le total de l’espace réellement libérable. Les dossiers imbriqués ne doivent pas être additionnés.

Les résultats reflètent le dernier scan, dont la date reste affichée. Relancer l’analyse après des changements. La date de modification ne permet pas de conclure qu’un fichier est inutilisé. Le moteur de nettoyage revérifie les chemins et les métadonnées, refuse les liens symboliques sur le chemin et déduplique les sélections parent/enfant avant tout déplacement.

Pas de dépendance externe ni de transmission réseau. DigUp a été évalué comme complément potentiel de recherche sémantique, mais n’est pas intégré : ses exclusions de caches, dossiers cachés et dépendances le rendent inadapté au rôle de scanner de stockage.

## Développement

```sh
bash scripts/test.sh
bash scripts/build.sh
open build/Clair.app
```

Les scripts utilisent le compilateur, le SDK macOS et XCTest de Xcode sélectionné par `xcode-select`. Les tests créent exclusivement des dossiers temporaires et utilisent des déplacements simulés pour le nettoyage.

Le projet Xcode se régénère avec XcodeGen :

```sh
xcodegen generate
xcodebuild -project Clair.xcodeproj -scheme Clair -configuration Debug -derivedDataPath build/Xcode CODE_SIGNING_ALLOWED=NO build
```

Le script utilise en priorité un certificat **Developer ID Application**, puis **Apple Development**, déjà présent dans le trousseau. `CLAIR_SIGN_IDENTITY` permet de choisir explicitement une identité. Sans certificat il revient à une signature ad hoc, avec avertissement : cette dernière change d’identité entre compilations et peut invalider les autorisations macOS. Le projet Xcode utilise par défaut une signature locale sans équipe imposée. Le script de release exige un certificat Developer ID Application.

Une compilation locale n’est pas automatiquement notarifiée. Après un changement de signature ou d’emplacement, macOS peut demander de réactiver Clair dans Accès complet au disque. Clair ne peut pas accorder lui-même cette autorisation et ne modifie jamais la base de permissions macOS. La procédure de distribution est décrite dans [docs/releasing.md](docs/releasing.md).

Pour vérifier le moteur en ligne de commande, sans nettoyage :

```sh
xcrun swiftc -O -whole-module-optimization -swift-version 6 Sources/CleanerCore/*.swift scripts/analyze.swift -o build/analyze-mac
build/analyze-mac --output build/analysis
```

Ce diagnostic parcourt le disque entier et produit un index, un rapport Markdown et la liste des 1 000 plus gros fichiers d’au moins 100 Mo. L’index reste complet. `--root` est réservé à la validation technique d’un périmètre ; ce choix n’est pas exposé dans l’app. Les autorisations du processus qui lance le diagnostic ne prouvent pas celles de Clair. Les fournisseurs cloud peuvent ralentir l’énumération de leurs métadonnées.


## Confidentialité et contribution

Aucun compte, serveur, suivi analytique ou envoi du contenu du disque. Les rapports
exportés contiennent vos chemins de fichiers : ne les partagez pas sans les relire.
Les sources sont sous [licence MIT](LICENSE). Consultez [CONTRIBUTING.md](CONTRIBUTING.md)
pour contribuer et [SECURITY.md](SECURITY.md) pour signaler une vulnérabilité en privé.

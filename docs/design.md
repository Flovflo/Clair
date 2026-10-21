# Clair — architecture et décisions

Clair sépare la mesure du disque, la décision de l’utilisateur et le déplacement dans la Corbeille.

- `StorageScanner` parcourt les noms avec readdir et les métadonnées avec lstat, sans suivre les liens symboliques, franchir les volumes montés ou ouvrir le contenu des fichiers. Une pile itérative remplace FTS pour éviter ses appels groupés getattrlistbulk sur iCloud. Il conserve les totaux des dossiers et une sélection des 300 plus gros fichiers en mémoire ; tous les chemins de fichiers réguliers sont persistés dans SQLite. Les erreurs d’accès sont comptées et explicites.
- `StorageIndex` fournit les pages de recherche et le contenu des dossiers sans garder des millions de fichiers en mémoire. `StorageBrowser` reste disponible pour les diagnostics ponctuels hors index.
- `DiskScanner` mesure les candidats connus, calcule une empreinte de métadonnées et revérifie chaque cible avant nettoyage. `CleanupPolicy` limite les chemins nettoyables ; une explication heuristique n’est jamais une autorisation de suppression.
- `CleanupSelection` retire les doublons et descendants déjà inclus dans un parent. `TrashService` utilise la Corbeille macOS et conserve le résultat de chaque déplacement et chaque erreur.
- `CleanerModel` publie l’état sur le MainActor ; la mesure s’exécute en arrière-plan. La barre latérale est construite à partir des sources réellement présentes, triées par volume décroissant.

Aucun scan automatique avant le premier choix de l’utilisateur. L’accès complet au disque se règle dans macOS et exige de relancer la copie installée. L’explorateur reste disponible pour les fichiers personnels et système, mais leur gestion passe par le Finder ou l’outil propriétaire.

La recherche sémantique DigUp est une option future distincte. Elle pourrait aider à retrouver un document, mais ne prouve ni son caractère inutile ni sa disponibilité ailleurs. Aucun modèle ou index supplémentaire n’est installé par Clair.

## Inventaire approfondi et rapport

`StorageIndex` utilise SQLite fourni par macOS. Un fichier temporaire reçoit toutes les métadonnées des fichiers réguliers et les totaux des dossiers. Après succès, il remplace atomiquement le précédent index. Une annulation ou une erreur conserve ce dernier. Un gestionnaire de progression SQLite interrompt aussi la création des index SQL. Les liens physiques restent visibles sous chaque chemin, avec leurs blocs comptés une seule fois et un indicateur de partage. Les anciens inventaires restent lisibles jusqu’au prochain scan. Les requêtes sont paginées et exécutées hors du MainActor, avec paramètres SQL liés pour les textes utilisateur. Aucun contenu privé de fichier n’est indexé.

`FileCategory` classe chaque fichier par usage/emplacement puis extension. Les totaux de catégories sont calculés sur les fichiers, sans addition de parents et enfants. `StorageInsights` identifie des racines explicables et supprime les recouvrements entre lignes du rapport ; le projet principal peut contenir plusieurs de ces lignes. Le rapport n’interprète pas un nom de dossier comme une preuve de supprimabilité. Les dates de modification ne sont pas des dates de dernière utilisation.

L’interface démarre sur le rapport, garde une recherche globale et expose les fichiers, dossiers lourds, sous-dossiers et pistes de tri. Le choix manuel d’un périmètre a été retiré de l’interface : le parcours principal analyse tout le Mac. Le contrôle préalable de l’accès complet ouvre uniquement une ressource TCC protégée sans lire son contenu ni modifier les permissions. Ce contrôle est une sonde, pas une API officielle de statut FDA.

## Configuration native

`SetupSheet` présente l’état de la sonde, le lien vers Accès complet au disque, l’aide pour ajouter la copie installée et la relance. Aucune permission n’est accordée par le code. La relance n’est autorisée qu’au repos ; un helper local attend la sortie du processus avant de rouvrir le même bundle. Le drapeau de reprise est enregistré avant la fermeture. Le rapport déjà persisté reste accessible si l’utilisateur reporte la configuration.

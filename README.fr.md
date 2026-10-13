<div align="center">
  <h1>WiFi Proxy Pilot</h1>
  <h3>Changement intelligent de proxy selon le Wi-Fi sous Windows</h3>
  <p>Un utilitaire Windows léger et moderne qui adapte automatiquement le proxy système aux SSID Wi-Fi, aux adresses de passerelle et aux règles que vous définissez.</p>

  ![Windows 11](https://img.shields.io/badge/Windows-11-0078D4)
  ![.NET 8](https://img.shields.io/badge/.NET-8-512BD4)
  ![WPF](https://img.shields.io/badge/UI-WPF-6557E8)
  [![Release](https://img.shields.io/github/v/release/jeffxuu/WiFiProxyPilot)](https://github.com/jeffxuu/WiFiProxyPilot/releases)
  [![Licence MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)
  [![GitHub Stars](https://img.shields.io/github/stars/jeffxuu/WiFiProxyPilot?style=flat)](https://github.com/jeffxuu/WiFiProxyPilot/stargazers)
</div>

**[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Tiếng Việt](README.vi.md)**

**Votre Wi-Fi change. Votre proxy suit.** Utilisez un proxy hébergé sur la passerelle des réseaux Wi-Fi ordinaires et une connexion directe sur les réseaux de votre choix. Gérez le tout depuis une interface WPF moderne ou la zone de notification.

> **v3.2.0-beta.1 est en développement.** Les captures montrent la véritable application WPF avec des données réseau simulées. La validation sur un réseau réel, à l'ouverture de session/en sortie de veille, ainsi que pour l'installation et la désinstallation reste distincte des tests de régression isolés. L'interface actuelle est en chinois simplifié ; les traductions du README ne signifient pas que l'interface est traduite. Le dépôt reste Private en attendant la décision de publication de son propriétaire. Les badges externes et Star History peuvent donc être indisponibles.

## Captures d'écran

![Vue d'ensemble : véritable application WPF, réseau simulé](docs/images/dashboard.png)

| Règles Wi-Fi | Paramètres |
| --- | --- |
| ![Aperçu des règles Wi-Fi](docs/images/rules.png) | ![Aperçu des paramètres](docs/images/settings.png) |

![Zone de notification : véritable menu avec des données simulées](docs/images/tray.png)

<details>
<summary>Aperçu du thème sombre</summary>

![Thème sombre : ancienne disposition de la vue d'ensemble WPF](docs/images/dashboard-dark.png)

</details>

Toutes les images sont des captures réelles de l'application dans un environnement isolé, **pas des preuves de connexion à un proxy réel**. La capture sombre utilise une disposition antérieure de la vue d'ensemble. La capture de la zone de notification montre le véritable menu de l'application avec les mêmes données simulées.

## Fonctions principales

- Reconnaît le Wi-Fi connecté et compare vos règles au SSID complet, sans tenir compte de la casse.
- Détermine la **passerelle IPv4 par défaut** de l'interface Wi-Fi physique actuelle, puis applique le port de proxy configuré, `7890` par défaut.
- Prévoit une connexion directe pour les réseaux choisis. Les nouvelles installations commencent **sans règle Wi-Fi intégrée** ; chaque règle peut être modifiée ou supprimée.
- Propose une interface WPF inspirée de macOS, des thèmes clair/sombre et une zone de notification avec un moniteur indépendant en arrière-plan.
- Distingue la gestion automatique, l'état du proxy manuel de Windows et les diagnostics TCP/HTTP facultatifs. Un proxy activé ne prouve pas l'accès à Internet.
- Enregistre la configuration de manière atomique et distingue « enregistré » de « appliqué par le moniteur ».
- Conserve la sauvegarde du proxy manuel initial et protège les modifications ultérieures effectuées par vous ou une autre application.
- Fournit le code source sous licence MIT pour permettre son inspection et les contributions.

## Téléchargement et installation

**[Télécharger la dernière version publiée : ancienne v3.0.0](https://github.com/jeffxuu/WiFiProxyPilot/releases/latest)** · **[Consulter les versions](https://github.com/jeffxuu/WiFiProxyPilot/releases)** · **[Artefacts de compilation v3.2](https://github.com/jeffxuu/WiFiProxyPilot/actions/workflows/build.yml)**

La v3.0.0 publiée contient l'ancienne interface et l'ancien comportement ; elle **n'inclut pas** l'interface WPF v3.2 présentée ici. v3.1.0 est une Draft Prerelease. Aucune version v3.2 n'est actuellement publiée. L'accès aux artefacts exige les droits sur le dépôt ; ces artefacts expirent et les brouillons ne sont pas des téléchargements publics. Vérifiez la version, les notes de publication et SHA256 avant l'installation. Le badge Release suit les versions publiées, pas la version en développement.

La plateforme prévue est **Windows 11 x64**, avec Windows PowerShell 5.1, le service WLAN et Windows Script Host. L'EXE autonome ne nécessite pas d'installer séparément .NET, Python, Node.js ou WebView2. Aucune compatibilité plus large avec Windows n'est affirmée. Les politiques d'une organisation peuvent restreindre les informations WLAN, le proxy ou les tâches planifiées. Les compilations actuelles ne sont pas signées ; gardez les protections de sécurité Windows activées.

Téléchargez l'EXE ou extrayez le ZIP, puis comparez son empreinte au fichier `SHA256.txt` fourni :

```powershell
Get-FileHash .\WiFiProxySwitcher.exe -Algorithm SHA256
```

L'exécutable conserve le nom `WiFiProxySwitcher.exe` pour assurer la compatibilité des mises à niveau. Lancez-le avec votre utilisateur Windows interactif habituel. Ouvrir la fenêtre v3.2 ne suffit pas à activer la gestion du proxy. N'installez pas pour votre compte quotidien en utilisant le compte d'un autre administrateur.

## Démarrage rapide

1. **Téléchargez** une compilation et vérifiez sa version et son empreinte.
2. **Configurez** le port d'un proxy déjà présent sur votre passerelle Wi-Fi et ajoutez les noms des réseaux qui doivent utiliser une connexion directe.
3. **Activez le changement automatique** après avoir examiné les paramètres que l'application va gérer.

**La passerelle doit réellement exécuter un service proxy. WiFi Proxy Pilot ne fournit ni serveur proxy ni nœuds VPN.** Avec un point d'accès Android, la passerelle IPv4 actuelle est détectée automatiquement. Renseignez le port d'écoute de l'application proxy du téléphone et autorisez les connexions de l'appareil Windows connecté. Un point d'accès seul n'est pas un proxy.

## Fonctionnement

```text
Wi-Fi connecté → Lire un état stable du SSID/de l'interface → Comparer les règles
  ├─ Règle de connexion directe trouvée → Désactiver le proxy manuel Windows
  └─ Aucune règle de connexion directe → Déterminer la passerelle IPv4 Wi-Fi actuelle
                                        → Appliquer passerelle + port configuré
```

Le moniteur vérifie le réseau actuel avant chaque changement pour éviter de réutiliser une ancienne passerelle après un changement de Wi-Fi. Un SSID inconnu, des routes manquantes ou des interfaces ambiguës entraînent le maintien des paramètres existants, une explication et de nouvelles tentatives. Une déconnexion confirmée désactive le proxy manuel. PAC et la détection automatique conservent leurs valeurs et peuvent encore influencer le routage des applications.

## Gestion des règles Wi-Fi

Ouvrez **Règles Wi-Fi** pour ajouter, renommer, supprimer ou ajouter le réseau actuel lorsqu'il est détecté de façon fiable. Une liste vide est autorisée. La comparaison porte sur le nom entier avec `OrdinalIgnoreCase`, et non sur un préfixe ou une sous-chaîne. Les espaces autorisés sont conservés ; le nom doit occuper entre 1 et 32 octets UTF-8 sans caractère de contrôle.

**Enregistrer et appliquer** vérifie les modifications concurrentes et écrit de manière atomique. « Enregistré » confirme l'écriture du fichier ; « Appliqué » exige un signal de vie récent et compatible du moniteur, portant la même révision et un réseau stable. Sinon, l'interface indique que l'application en arrière-plan est en attente. Annuler abandonne les changements non enregistrés. Les règles supprimées ne sont pas réintroduites silencieusement.

## Zone de notification et modes de proxy

| Action | Effet |
| --- | --- |
| Activer le changement automatique | Observer de nouveau le réseau et gérer le proxy manuel selon vos règles |
| Mettre en pause | Arrêter les écritures automatiques ; conserver le proxy actuel |
| Connexion directe | Suspendre la gestion et désactiver uniquement le proxy manuel Windows |
| Vérifier maintenant | Demander une nouvelle observation du réseau et une évaluation stable |
| Fermer la fenêtre | La masquer dans la zone de notification par défaut ; le moniteur continue |
| Quitter l'interface | Fermer l'interface et la zone de notification ; le moniteur indépendant continue |
| Restaurer la configuration initiale | Arrêter la gestion et restaurer la sauvegarde initiale avec contrôle des conflits |

L'intention de pause ou de connexion directe persiste au redémarrage de l'interface et à l'ouverture de session. Le démarrage du moniteur à la connexion et le démarrage de l'icône de notification sont deux réglages indépendants.

**Strict** applique la règle choisie et signale les échecs de diagnostic sans désactiver silencieusement le proxy. **Safe** peut revenir à une connexion directe après le nombre configuré d'échecs consécutifs ; une partie du trafic peut alors contourner le proxy. Un diagnostic inconnu ne signifie pas un rétablissement. Le diagnostic TCP prouve seulement qu'une connexion à un port est possible ; le diagnostic HTTP effectue une véritable requête via le proxy vers l'URL HTTP configurée. Aucun ne garantit le fonctionnement de chaque site ou application.

## Restauration et désinstallation

La sauvegarde du proxy manuel initial se trouve dans `state/proxy-before-install.json`, sous le répertoire d'installation. Les mises à niveau la conservent avec vos règles ; elles ne créent pas une nouvelle sauvegarde « initiale ». Les modifications de configuration conservent le fichier valide précédent. Gardez ces fichiers locaux privés.

Pour une installation existante, ouvrez l'EXE candidat et utilisez **Paramètres → Opérations avancées → Réparer l'installation / Mettre à niveau**. Ne désinstallez pas d'abord et ne remplacez pas votre configuration par les valeurs du dépôt. Consultez la [migration de configuration](docs/CONFIG_MIGRATION.md).

Utilisez **Restaurer la configuration initiale**, **Paramètres → Opérations avancées → Désinstaller** ou Applications installées de Windows. La restauration et la désinstallation comparent les paramètres actuels aux valeurs initiales et aux dernières valeurs écrites par l'outil. Les modifications externes ultérieures provoquent un conflit au lieu d'être écrasées. La restauration forcée est un choix explicite ; la désinstallation peut aussi conserver le proxy actuel. La suppression se limite aux tâches et entrées de démarrage appartenant au produit ainsi qu'aux fichiers vérifiés, pour protéger les fichiers étrangers ou modifiés par l'utilisateur. Le mode direct conserve la sauvegarde initiale.

## Sécurité et confidentialité

- Les SSID, la configuration du proxy, l'état et les journaux sont traités localement ; aucun compte cloud ou service d'analyse n'est nécessaire.
- L'application ne collecte pas les mots de passe Wi-Fi. Les diagnostics facultatifs se connectent au proxy choisi et, en mode HTTP, à l'URL que vous configurez.
- La sauvegarde du proxy initial est conservée. L'installation et les tâches respectent l'identité de l'utilisateur actuel et les contrôles d'autorisation.
- L'application gère le **proxy manuel** de l'utilisateur Windows actuel ; elle ne modifie ni DNS, ni routes, ni règles de pare-feu.
- Les journaux et diagnostics peuvent contenir des identifiants réseau. Vérifiez-les et anonymisez-les avant de les partager.

Les commits historiques et les anciens documents de publication contiennent des exemples réseau et des chemins de machine. Garder le dépôt Private ne les supprime pas. La publication exige une revue séparée par le propriétaire de [l'audit avant publication](docs/PUBLIC_REPOSITORY_AUDIT.md). Pour signaler un problème de sécurité, consultez [SECURITY.md](SECURITY.md).

## Questions fréquentes

**Comment changer automatiquement de proxy selon le Wi-Fi sous Windows 11 ?** Configurez le port du proxy de la passerelle, ajoutez les SSID de connexion directe et activez le changement automatique. Le moniteur évalue les changements Wi-Fi stables et applique le proxy manuel Windows pour l'utilisateur actuel.

**Comment utiliser la passerelle d'un point d'accès Android comme proxy Windows ?** Lancez un service proxy distinct sur le téléphone, autorisez les appareils connectés à y accéder et indiquez son port dans Pilot. La passerelle est détectée sur l'interface Wi-Fi actuelle. Si elle est inaccessible, vérifiez le service et le pare-feu du téléphone.

**WiFi Proxy Pilot inclut-il un VPN ?** Non. Il gère la configuration du proxy manuel Windows ; vous fournissez le service. Les applications utilisant leur propre proxy ou ignorant les paramètres Windows peuvent se comporter autrement.

**Pourquoi le proxy est-il activé sans accès à Internet ?** La passerelle peut ne pas héberger de proxy, le port peut être incorrect, le service peut être arrêté ou la destination défaillante. Vérifiez séparément les diagnostics TCP/HTTP. Pause conserve le réglage ; Direct désactive le proxy manuel. PAC peut encore influencer le trafic.

**Comment contourner le proxy sur certains réseaux Wi-Fi ?** Ajoutez leurs SSID complets dans Règles Wi-Fi, puis enregistrez/appliquez. Toutes les règles sont modifiables et supprimables ; une liste vide est valide.

**Comment restaurer les paramètres proxy de Windows ?** Choisissez Restaurer la configuration initiale et examinez les éventuels conflits dus à des modifications externes. Direct désactive seulement le proxy manuel ; il ne restaure pas le serveur initial ni la liste d'exceptions.

**L'application continue-t-elle après la fermeture de la fenêtre ?** Oui. X masque la fenêtre dans la zone de notification par défaut. Quitter l'interface laisse également le moniteur indépendant actif ; utilisez Pause ou Restaurer pour modifier la gestion en arrière-plan.

**Pourquoi le réseau actuel n'est-il pas lisible ?** Les autorisations WLAN/localisation, les politiques de l'organisation, des routes absentes, un moniteur arrêté ou un ancien signal de vie peuvent empêcher un état fiable. L'interface indique la raison et la dernière observation valide sans présenter d'anciennes données comme actuelles.

**Qu'est-ce qui a été testé ?** Consultez les [résultats v3.2](docs/TEST_RESULTS_V3_2.md), les [mesures de performance](docs/PERFORMANCE_V3_2.md) et la [liste de vérification de publication](docs/RELEASE_CHECKLIST.md). Les contrôles isolés ne remplacent pas la validation d'un réseau ou d'une installation réels ; un objectif de performance n'est pas une mesure obtenue.

## Star History

Si WiFi Proxy Pilot facilite votre travail, pensez à ajouter une étoile au projet.

<a href="https://star-history.com/#jeffxuu/WiFiProxyPilot&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
    <img alt="WiFi Proxy Pilot Star History" src="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
  </picture>
</a>

Le SVG officiel en direct utilise les véritables données GitHub de ce dépôt. Tant que celui-ci reste Private, le service externe ne peut pas rendre son historique visible à tous. Il faudra le vérifier après publication ; aucune étoile ni croissance n'est inventée et un historique vide n'est pas remplacé par des données fictives. Consultez le [guide officiel d'intégration](https://www.star-history.com/blog/how-to-use-github-star-history/).

## Contributions et feuille de route

Les utilisateurs ayant accès au dépôt peuvent soumettre des issues et des pull requests. Indiquez la compilation, le résultat attendu et observé ainsi que des preuves anonymisées. Consultez [CONTRIBUTING.md](CONTRIBUTING.md) pour la compilation et le processus de revue sous Windows. N'incluez pas de configuration personnelle, de sauvegarde du proxy, d'identifiants secrets ou de journaux non anonymisés.

Travaux prévus : validation réelle des mises à niveau, ouvertures de session, sorties de veille et désinstallations ; derniers contrôles d'accessibilité et de disposition WPF ; amélioration des performances de démarrage ; et traduction de l'interface. Ce sont des projets, pas des fonctions livrées ; la mise à jour automatique n'est pas implémentée.

Compilez avec le SDK indiqué dans `global.json` et Windows PowerShell :

```powershell
powershell.exe -NoProfile -File tests\Run-Tests.ps1 -ResultPath artifacts\engine-results.json
powershell.exe -NoProfile -File release\Build.ps1
```

La compilation crée un EXE autonome `win-x64` sans l'installer ni modifier le proxy de la machine. Les identités existantes `WiFiProxySwitcher` pour l'installation, le registre, les mutex et les tâches sont conservées pour la compatibilité.

## Licence

Le code source du projet est sous licence [MIT](LICENSE). Les éléments tiers conservent leurs propres conditions ; consultez les [mentions relatives aux tiers](docs/THIRD_PARTY_NOTICES.md). Les polices sont utilisées depuis Windows et ne sont pas redistribuées.

# Modifications de ce fork

Fork de [PanOptikuum/DoodlebookOS](https://github.com/PanOptikuum/DoodlebookOS) (v0.9.0-alpha, auteur
d'origine : Maciej Kujawiński, GPL-3.0-or-later), modifié par **zeldarrr** en novembre 2026.
Les fichiers modifiés gardent leur en-tête de licence d'origine ; la liste ci-dessous tient lieu
d'avis de modification au sens de la GPL-3.0 (§ 5a).

## Installation
- `setup/` : installeur sans droits admin en **un seul fichier** (`DoodlebookOS-Installer.run`, voir
  `setup/make-installer.sh`), sauvegarde automatique du bureau (`theme-switch`), profil exporté
  (`setup/profile/`, sans données personnelles), modules C++ précompilés vérifiés avant usage
  (version de Plasma + `ldd -r`), sinon compilés si les outils sont là.
- Vérifie les paquets dont les widgets ont besoin (son, réseau, Bluetooth, KDE Connect, Pillow, PyGObject…)
  et propose de les installer en une fois (pacman, dnf, apt, zypper) ; testé sur Arch (Plasma 6.8.3, Qt 6.12).
  Dock et widget Appareils se chargent même sans KDE Connect.
- Mises à jour automatiques signées (`doodlebookos-update`, minuteur quotidien, installation à la
  connexion suivante, `setup/release.sh` pour publier).
- Faux liens (fichiers texte) de l'archive remplacés par de vrais liens symboliques (curseurs,
  icônes de dossiers, fonds d'écran `.png`).

## Couleurs et icônes
- **Material You** (`doodlebookos-materialyou`) : couleurs tirées du fond d'écran (HCT + Score de
  Material Color Utilities réécrits en Python), schéma de couleurs, Konsole, écran de verrouillage
  flouté, applis GTK (`extras/gtk`), barre de titre unifiée.
- **Thème d'icônes généré** (`doodlebookos-m3icons`) façon icônes à thème d'Android 13+ : rond tonal
  + glyphe (Simple Icons, Material Symbols ou initiale), dossiers et types de fichiers M3, base
  Tela-circle ; 16 **formes Material 3 Expressive** (`doodlebookos-icons shape …`), repli d'icônes
  corrigé (`mirror_fallbacks`).
- Packs au choix : `doodlebookos-icons material|tela-circle|colloid`.
- **« Fond d'écran et style »** (appli `doodlebookos-style`, comme sur Android) : fond d'écran,
  Material You, **styles de palette** d'Android (Tonal Spot, Vibrant, Expressive, Fruit Salad,
  Rainbow, Content, Neutral, Monochrome), **contraste** standard / moyen / élevé, clair/sombre et
  forme des icônes, avec aperçu ; en ligne de commande : `doodlebookos-materialyou variant|contrast`.
- **Applis tierces** aux couleurs du fond : accent de Zen, thème « DoodlebookOS Material You » pour
  VS Code / VSCodium et pour Kate / KWrite (à choisir une fois, suit ensuite le fond), Flatpak
  autorisés à lire les couleurs GTK/KDE et les icônes.

## Écrans système
- **Démarrage** : indicateur de chargement M3 Expressive (forme qui se transforme).
- **Verrouillage** (fond `org.doodlebookos.lockscreen`) : grande horloge sur deux lignes en
  Google Sans Flex qui « respire » au réveil, minutes qui roulent, date et météo ; le champ de mot
  de passe de Plasma passe devant, l'horloge se floute derrière.
- **Menu d'extinction** façon Android : grandes tuiles tonales (verrouiller, veille, déconnexion,
  redémarrer, éteindre) qui changent de forme au survol, clavier complet.
- **Écran de connexion SDDM** M3 Expressive, optionnel (`doodlebookos-setup.py --sddm`, droits admin
  demandés) : horloge, avatar, champ pilule, secousse sur mauvais mot de passe, puces de session.
- **Animation de charge** au branchement : onde aux couleurs du fond et niveau qui apparaît sur un
  ressort.
- **Capture d'écran façon Android** (Impr. écran ; Meta+Maj+S, touche « capture » des portables
  et tuile des Réglages rapides pour une zone ; `doodlebookos-screenshot`) : la capture rétrécit
  dans le coin, carte « Modifier » / fermer / glisser ; Spectacle passe sur Ctrl+Impr. écran.
- **Thème sonore** original et discret (`themes/sounds`, 38 sons synthétisés, repli sur Ocean) ;
  **Google Sans Code** fournie pour le texte à chasse fixe.

## Bureau et widgets
- **Dock / lanceur** : index et recherche tolérante, dossiers, badges de notifications, résultats
  KRunner + recherche web (navigateur par défaut), réglages (pages Dock et Lanceur), formes M3 des
  boutons, icônes rafraîchies dès que le thème d'icônes change, lancement ≈ 17 ms. Plus de
  catégories : une seule grille A–Z sous la recherche (les catégories servent encore à nommer les
  dossiers). Barre de recherche M3 (loupe → flèche retour, bouton effacer à ressort), entrée du
  lanceur en « emphasized decelerate », info-bulles du dock qui jaillissent de l'icône.
- **Barre du haut** : bureaux virtuels (`Workspaces`), batteries des appareils et téléphones
  KDE Connect (`Devices`), pilule média, Phone Hub, réglages rapides (mode jeu, Material You…),
  OSD Material 3, couleur adaptée au fond d'écran par une unité systemd `.path` (plus de sondage).
- **Menu des applis en arrière-plan** (clic droit sur Discord, Steam… dans la barre du haut) : menu
  Material 3 Expressive construit depuis le DBusMenu de l'appli (`tray/TrayMenu.qml`) — groupes
  tonals séparés par des espaces, cases et boutons radio M3, sous-menus en axe partagé X, lignes
  en cascade, navigation clavier complète ; dernier menu gardé en cache (ouverture immédiate),
  repli sur le menu de l'appli quand elle n'expose pas de DBusMenu.
- Nouveaux widgets : Note, Stockage, Image (formes M3, diaporama), Jeux, Calendrier, Horloge,
  Média, Système — avec page « Apparence » commune.
- Notifications : barre de délai M3 et animation de sortie Expressive.
- Calendrier : changement de mois en axe partagé X ; Horloge : chiffres qui défilent à chaque minute.
- Corrections : presse-papiers des réglages rapides (identifiant `clip` qui masquait la propriété
  `clip`), menu d'une fenêtre du dock (fermeture avant l'appel au modèle, menu chargé à la demande).

## Fenêtres et applis
- Décoration : boutons M3 Expressive, coins animés, ombre réglable (`ShadowOpacity`,
  `ShadowSpread` dans `doodlebookosrc`).
- Style Qt : rayons 12/16, animations, sélection tonale, coins arrondis des vues, barres de
  défilement discrètes, champs intégrés sans fond, **menus groupés M3 Expressive** (cartes
  arrondies séparées par des espaces, plus de traits), **interrupteurs M3 en vraie taille**
  (piste contourée visible quand ils sont coupés), vraies cases à cocher M3 dans les menus et les
  titres de groupes, boutons radio M3. Se compile aussi sans extra-cmake-modules.
- **Fenêtres façon Android** : une appli lancée depuis le dock ou le lanceur grandit depuis
  l'icône cliquée ; elle se referme et se réduit dans son icône du dock.
- **Sélecteur de fichiers** (celui des navigateurs, via xdg-desktop-portal-kde) : emplacements et
  fil d'Ariane en pilules tonales, liste de fichiers sur une surface arrondie (la propriété
  `_breeze_borders_sides` que KIO remet après l'affichage ne l'aplatit plus), curseur de zoom sans
  graduations serrées ; réglages par défaut appliqués une seule fois par l'installeur (vue détaillée,
  dossiers d'abord, aperçus, icônes 32 px, panneau 196 px).
- Scripts / effets KWin : animations Material (`doodlebookos_motion`), coins d'écran arrondis,
  mode jeu automatique, mode concentration, sélecteur de fenêtres.
- **Popups M3 Expressive** (`doodlebookos_popups`, remplace « Popups en fondu ») : les panneaux
  (réglages rapides, notifications, agenda, menus du tray, lanceur, Phone Hub) se déploient depuis
  la barre qui les porte et depuis le bouton cliqué, sur un ressort (léger dépassement), puis se
  replient plus vite à la fermeture ; menus des applis ouverts depuis le coin le plus proche du
  pointeur ; bulles en fondu. Le flou reste pendant toute l'animation (force 4 : 2 passes).
  Transformations GPU uniquement, coupées en économie d'énergie.
- **Ressorts M3 Expressive** dans les widgets (`motion.js` : ressorts amortis de
  `MotionScheme.expressive()` d'Android, calculés à partir d'un seul minuteur par popup) : le
  contenu se pose par rangées du haut vers le bas (plus de « pop » tuile par tuile), sous-pages en
  axe partagé X, pochette du média qui se pose, cartes du presse-papiers animées une seule fois.

## Économie d'énergie
- `doodlebookos-powersave` (service utilisateur, sans sondage) : en profil « Économie d'énergie »
  (tuile, applet batterie ou PowerDevil sur batterie), flou KWin coupé et animations « instantanées »
  partout (KWin, Plasma, applis, décoration) ; valeurs d'origine restaurées en quittant le profil.
- Thème Plasma : sans flou, popups, menus et bulles sont opaques (fonds de base à 100 % ; les
  variantes `translucent/` restent à 82 % quand le flou est actif).
- Widgets : les durées d'animation suivent la vitesse globale de Plasma (instantané = aucune
  animation) ; titres défilants, vague du lecteur, « respiration » de la barre, tremblement du mode
  édition et ressorts du dock s'arrêtent quand les animations sont coupées.

## Outils
- `theme-switch` (profils de thème, retour arrière), `doodlebookos-gamemode`,
  `doodlebookos-focus`, `doodlebookos-desktop-shortcuts` (AZERTY), priorité audio des
  appels vocaux (`extras/systemd/voice-priority`).
- Mesures : `setup/slowmo-test.py` (animations au ralenti photographiées, vitesse toujours
  remise) et `setup/perf-check.py` (CPU au repos par processus, puissance sur batterie).

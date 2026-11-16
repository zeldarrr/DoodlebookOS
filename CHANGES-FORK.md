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

## Bureau et widgets
- **Dock / lanceur** : index et recherche tolérante, dossiers, badges de notifications, résultats
  KRunner + recherche web (navigateur par défaut), réglages (pages Dock et Lanceur), formes M3 des
  boutons, icônes rafraîchies dès que le thème d'icônes change, lancement ≈ 17 ms.
- **Barre du haut** : bureaux virtuels (`Workspaces`), batteries des appareils et téléphones
  KDE Connect (`Devices`), pilule média, Phone Hub, réglages rapides (mode jeu, Material You…),
  OSD Material 3, couleur adaptée au fond d'écran par une unité systemd `.path` (plus de sondage).
- Nouveaux widgets : Note, Stockage, Image (formes M3, diaporama), Jeux, Calendrier, Horloge,
  Média, Système — avec page « Apparence » commune.
- Notifications : barre de délai M3 et animation de sortie Expressive.

## Fenêtres et applis
- Décoration : boutons M3 Expressive, coins animés, ombre réglable (`ShadowOpacity`,
  `ShadowSpread` dans `doodlebookosrc`).
- Style Qt : rayons 12/16, animations, sélection tonale, coins arrondis des vues, barres de
  défilement discrètes, champs intégrés sans fond.
- Scripts / effets KWin : animations Material (`doodlebookos_motion`), coins d'écran arrondis,
  mode jeu automatique, mode concentration, sélecteur de fenêtres.

## Outils
- `theme-switch` (profils de thème, retour arrière), `doodlebookos-gamemode`,
  `doodlebookos-focus`, `doodlebookos-desktop-shortcuts` (AZERTY), priorité audio des
  appels vocaux (`extras/systemd/voice-priority`).

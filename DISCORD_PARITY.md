# DISCORD_PARITY.md — Audit de parité Discord (client Flutter Daccord)

Fichier permanent. Relu au début de **chaque** session, mis à jour après **chaque** lot.
Branche de travail : `discord-parity` (créée depuis `idris/main` @ `9d52a22a`, tag de
sauvegarde `backup/pre-discord-parity-2026-11-03`).

## 0. Règles (rappel)

- Un élément n'est ✅ que si la comparaison visuelle (section 5 de la mission) a été faite
  contre une capture de `docs/discord-ref/`. Aucun ✅ n'est posé dans cet audit : aucune
  comparaison côte à côte n'a encore été faite.
- Statuts : ❌ absent · ⚠️ partiel · ✅ identique (vérifié par capture) · 🚫 impossible
  (raison + alternative).
- Priorités : **P0** partage d'écran / Live (friction actuelle) · **P1** disposition, messages,
  vocal · **P2** menus, raccourcis, paramètres, notifications · **P3** confort.
- « à confirmer » = point non couvert par une capture Discord ; il reste tel quel jusqu'à
  capture.
- Interdits : logo/nom/sons/polices/SVG/code Discord. Équivalents libres uniquement.

## 1. Source de vérité : captures Discord

Dossier `docs/discord-ref/` (**ignoré par git** : les captures contiennent vos amis, vos
serveurs et votre compte ; elles restent locales). Prises le 2026-11-03 sur **Discord web**
dans votre Chrome (même interface que le client desktop), fenêtre 1600×900, viewport
**1568×711** (à reproduire pour les captures de l'app). Thème sombre par défaut, langue EN.

| Fichier | Contenu |
|---|---|
| `desktop-home-friends.jpg` | Accueil DM : liste des conversations, onglets Friends, Active Now |
| `desktop-rail-hover-tooltip.png` | Barre des serveurs, icône survolée (carré arrondi + tooltip à droite + pilule) |
| `desktop-server-text-channel-members.jpg` | Serveur (non admin) : colonne salons, en-tête, messages, liste des membres par rôle |
| `desktop-owner-server-text-channel.jpg` | Serveur dont vous êtes propriétaire : icônes de survol sur salon/catégorie |
| `desktop-channel-list-hover-voice.png` | Survol d'un salon vocal (icônes chat + inviter) |
| `desktop-message-hover-actionbar.png` / `-own.png` | Barre d'actions au survol (autre / propre message) |
| `desktop-menu-message.jpg` / `-own.jpg` | Clic droit message (autre / propre) |
| `desktop-menu-server-icon.jpg` / `-owner.jpg` | Clic droit icône serveur (membre / propriétaire) |
| `desktop-menu-server-header.jpg` / `-owner.jpg` | Menu du nom du serveur (membre / propriétaire) |
| `desktop-menu-text-channel.jpg` / `-owner.jpg` | Clic droit salon texte |
| `desktop-menu-voice-channel.jpg` / `-owner.jpg` | Clic droit salon vocal |
| `desktop-menu-category.jpg` / `-owner.jpg` | Clic droit catégorie |
| `desktop-menu-member.jpg` / `desktop-menu-member-self-owner.jpg` | Clic droit membre (autre / soi, propriétaire) |
| `desktop-profile-popout.jpg` | Popout de profil au clic sur un membre |
| `desktop-user-panel-popup.jpg` / `desktop-status-picker.jpg` | Carte compte depuis le panneau utilisateur + sous-menu statut |
| `desktop-emoji-picker.jpg` / `desktop-gif-picker.jpg` / `desktop-sticker-picker.jpg` | Sélecteur unifié GIF / Stickers / Emoji |
| `desktop-composer-attach-menu.jpg` | Menu « + » du composeur |
| `desktop-search-filters.jpg` | Boîte de recherche d'en-tête + popover de filtres |
| `desktop-pinned-popover.jpg` / `desktop-threads-popover.jpg` / `desktop-channel-notification-popover.jpg` / `desktop-inbox-popover.jpg` | Popovers d'en-tête |
| `desktop-quick-switcher.jpg` | Ctrl+K |
| `desktop-settings-sidebar-bottom.png`, `desktop-settings-voice-1..6`, `desktop-settings-appearance-1..2`, `desktop-settings-notifications.jpg` | Paramètres utilisateur (modale 2026 : Account, Data & Privacy, Messaging Permissions, Notifications, Billing…, Experience : Voice & Video, Appearance, Accessibility, System, Language & Time ; Games & Apps ; Developer ; Log Out) |
| `desktop-server-settings-profile.jpg`, `-soundboard.jpg`, `-owner-sidebar-top.jpg`, `-owner-sidebar-bottom.jpg`, `-roles.jpg` | Paramètres serveur plein écran (bouton ✕ ESC en haut à droite, menu latéral) |
| `desktop-voice-lobby.jpg` | Salon vocal vide (« No one is currently in voice », bouton Join Voice) |
| `desktop-voice-connected-sidebar.jpg`, `desktop-voice-panel-userpanel-zoom.png` | Participant sous le salon vocal, panneau « Voice Connected », panneau utilisateur « In voice » |
| `desktop-call-view-idle.jpg` / `desktop-call-view-controlbar.jpg` | Vue d'appel (tuile + panneau activités) et barre de contrôle en bas |
| `desktop-menu-voice-participant-sidebar.jpg` / `desktop-menu-voice-tile.jpg` | Clic droit participant (ligne / tuile) |
| `desktop-stream-own-started.jpg` | **Lot D** (prises le 2026-11-03, Discord web, viewport 1568×711) : mon stream vient de démarrer — tuile stream + LIVE, badge LIVE dans la liste, carte « Go Live » dans le panneau vocal, panneau utilisateur « Sharing their screen » |
| `desktop-stream-live-badge-hover.jpg` | Survol de la ligne LIVE : carte « Streaming Now » (badge LIVE, miniature, bouton « You're Streaming! » / « Watch Stream ») |
| `desktop-stream-share-button-menu.jpg` / `desktop-stream-controlbar-chevron-menu.jpg` | Menu du bouton partage actif (panneau vocal) et du chevron de la barre d'appel : Stop Streaming (rouge) / Change Stream / Report Problem |
| `desktop-stream-own-hover-controlbar.jpg` | Survol de la vue d'appel en stream : pilule « 720P 30FPS » + LIVE en haut à droite de la tuile, pilule nom + icône écran, « … » bas-droit, barre de contrôle (partage vert avec chevron, pop-out + plein écran à droite) |
| `desktop-stream-own-tile-menu.jpg` | « … » de ma tuile stream : Stop Streaming / Change Stream / Pop Out Stream / More Options › |
| `desktop-stream-own-focused.jpg` | Clic simple = focus : en-tête « General • avatar X's Screen », pilule « 720p 30FPS LIVE » à droite, bande 16:9 avec chevron + icône participants, loupe bas-droit |
| `desktop-stream-own-fullscreen.jpg` | Plein écran (bouton bas-droit) : même disposition, tout le reste masqué, bouton « quitter » bas-droit |
| `desktop-stream-focus-camera-tile.jpg` | Clic sur une tuile de la bande = elle prend le focus |
| `desktop-stream-focus-strip-collapsed.jpg` | Chevron replié : tuile focus bord à bord, en-tête en dégradé, vignette de l'autre tuile en bas à droite, chevron ∧ en bas |
| `desktop-stream-popped-out-main.jpg` | Après « Pop Out » : fenêtre séparée (hors capture), la fenêtre principale revient sur #general |
| `desktop-stream-others-channel-list.jpg` | Liste de salons avec **trois autres** membres en stream (badges LIVE, icône d'activité) |
| `official-share-picker-step1.png`, `official-share-picker-step2.png` (+ `-light.png`) | **Images officielles Discord** (article d'aide « Go Live and Screen Share », blog Discord) : fenêtre « Screen Share » du client desktop, étape 1 (onglets Applications / Screens / Capture Devices, grille 2 colonnes, Cancel / Go Live) et étape 2 (What you're streaming + Change, info son, Streaming channel, Notify friends, Stream quality : préréglage + 720/1080/1440/SOURCE + 15/30/60, Clips, Hide stream preview, Back / Go Live) |
| `official-watch-stream-card.png` | Carte au survol d'un **autre** streamer : aperçu, activité, bouton « Watch Stream », « PROTIP: Double click user to watch » |
| `official-watching-stream-focus.png`, `official-focus-view.png` | Stream regardé en focus : bande 16:9 (tuile stream avec LIVE + « … », caméra, avatar), pilule chevron + icône membres au-dessus de la bande, volume du stream en bas à droite |
| `official-watched-stream-menu.png` | Clic droit sur un stream regardé : Stop Watching / Mute ☐ / Stream Volume (slider) / Show Non-Video Participants ☑ / Report Problem |
| `official-live-badge.png` | Zoom du badge LIVE en bout de ligne |

### 1.1 Captures manquantes (à fournir ou à faire ensemble)

Impossible pour moi sans effet de bord sur votre compte Discord (nécessite un 2ᵉ participant,
un stream réel, ou votre téléphone). Tant qu'elles manquent, les points concernés restent
« à confirmer ».

Desktop (il faut un ami en vocal, ou vous + moi sur votre serveur « Idriss + Ichraq ») :
1. Vue d'appel avec **2+ participants** (grille, anneau vert quand quelqu'un parle, icônes micro/casque sur les tuiles).
2. ~~Partage d'écran — fenêtre de sélection du client desktop~~ → couvert par les images officielles Discord (`official-share-picker-step1/2`) ; une capture de votre client desktop reste bienvenue pour les détails de thème sombre.
3. ~~Streamer : aperçu de son propre stream + menu~~ → fait le 2026-11-03 (`desktop-stream-own-*`).
4. ~~Liste des salons : badge LIVE + survol~~ → fait (`desktop-stream-live-badge-hover`, `desktop-stream-others-channel-list`, carte d'un autre streamer : `official-watch-stream-card`).
5. Vue d'appel : stream regardé → images officielles (`official-watching-stream-focus`, `official-watched-stream-menu`) ; reste la **tuile de stream non regardé** (bouton Watch Stream dans la grille) et le **compteur de spectateurs** éventuel, qui demandent un second participant.
6. **Deux streams simultanés** (second participant).
7. **Soundboard** ouvert depuis le vocal (grille emoji + nom, recherche, favoris, volume) et indication sur l'avatar de celui qui joue.
8. ~~Mode focus + plein écran + pop-out~~ → fait (`desktop-stream-own-focused`, `-fullscreen`, `-popped-out-main`) ; reste la fonction de l'icône « participants » sur la bande.
9. Message avec **réactions** (survol d'une réaction = tooltip des réacteurs), **réponse** avec aperçu, message **épinglé**, séparateur « New Messages » + barre « jump to present ».
10. **Glisser-déposer** d'un fichier (overlay « Upload to #channel ») et chips de pièces jointes.
11. **Confirmation de suppression** d'un message.
12. **Ctrl+/** liste des raccourcis (l'extension Chrome n'a pas transmis Ctrl+/ ; à capturer dans l'app desktop).
13. Fenêtre **redimensionnée** à ~1100 px et ~900 px (disparition de la liste des membres / colonne salons).
14. Paramètres : **Keybinds**, **Chat (Messages / Chat Box)**, **Accessibility**, barre « Careful — you have unsaved changes! » (modifier un champ sans sauver).
15. **Profil complet** (View Full Profile), **statut personnalisé** (dialogue), **Edit Profile**.
16. **Éditeur de salon** (Edit Channel : Overview / Permissions / Invites / Integrations) et **éditeur de rôle** (Display / Permissions / Manage Members).
17. **Fils** : panneau latéral d'un fil ouvert ; **forum** ; **sondage** ; **message vocal**.
18. Thème **clair** (si vous l'utilisez ; sinon on reste en sombre).

Android (depuis votre téléphone, en PNG) :
19. Accueil (onglets du bas Servers / Messages / Notifications / You), liste des serveurs + salons,
    un salon texte, clavier ouvert, menu long-press sur un message, vocal (feuille du bas),
    partage d'écran mobile, paramètres utilisateur, profil.

## 2. Inventaire de l'existant

### 2.1 Client Flutter (`lib/features/*`) — écrans, panneaux, menus, dialogues

| Zone | Fichier | Rôle |
|---|---|---|
| Accueil | `spaces/views/accord_home.dart` | écran 3 colonnes, 3 modes (large ≥920, moyen 680-919, compact <680), tiroirs, panneau de fil |
| Barre serveurs | `accord_home_rail.dart`, `_rail_tiles.dart`, `_rail_folders.dart`, `rail_draggable.dart` | rail 72 px, tuiles 48, dossiers, drag, menus, feuille « serveurs masqués », dialogue couleur dossier |
| Colonne salons | `accord_home_channels.dart`, `_channel_rows.dart`, `_channel_drag.dart` | en-tête + menu, bannière, Events, catégories, lignes, redimensionnement 180-420 |
| Onglets | `accord_home_tabs.dart` | bande d'onglets de salons ouverts (pas d'équivalent Discord) |
| Navigation | `accord_home_navigation.dart`, `utils/home_shortcuts.dart`, `quick_switcher.dart`, `keyboard_shortcuts_dialog.dart` | raccourcis, Ctrl+K, Ctrl+/ |
| Recherche | `accord_search.dart` | dialogue (messages + salons) |
| Espace | `accord_space_settings*.dart`, `accord_role_management.dart`, `accord_invites.dart`, `accord_ban_list.dart`, `accord_audit_log.dart`, `accord_reports.dart`, `accord_emoji_management.dart`, `accord_webhooks.dart`, `accord_soundboard.dart`, `accord_transfer_ownership.dart`, `accord_channel_reorder.dart`, `accord_gates.dart`, `welcome_screen.dart`, `space_events*.dart`, `accord_discovery.dart` | paramètres serveur (page défilante 2 colonnes, pas de menu latéral), rôles (dialogue 720×560), invitations, bans, audit, signalements, emojis, webhooks, soundboard (dialogue), transfert, réordonner, gates NSFW/règles, écran de bienvenue, événements, découverte |
| Salons | `channels/views/channel_context_menu.dart`, `channel_management.dart`, `channel_permissions*.dart`, `channel_member_picker_dialog.dart` | menus salon/catégorie, créer/éditer/supprimer, permissions |
| Membres | `member/views/accord_member_list.dart`, `accord_member_popout.dart` + `member_popout/sections.dart`, `profile_extras.dart`, `accord_member_avatar.dart` | liste 240 px (rôles hissés → « Members » → Offline), popout 360 px, bande de thème, pastille |
| Messages | `messaging/views/message_pane/*` (pane, rows, actions, editing, handlers, composer*, mention_popup, reactions, dividers, attachments, mute_button) | zone centrale complète |
| Messages (autres) | `emoji_picker*.dart`, `stickers.dart`, `pinned_messages.dart`, `forward_message_dialog.dart`, `thread_view*.dart`, `forum_view.dart`, `post_composer_dialog.dart`, `poll_view.dart`, `image_lightbox.dart`, `voice_message_recorder.dart`, `command_picker.dart`, `message_components.dart`, `inline_video_player.dart`, `inline_audio_player.dart`, `youtube_*`, `box/accord_embed_box.dart`, `box/accord_markdown_box.dart`, `box/accord_message_markup.dart`, `message_media_gate.dart`, `encrypted_attachment.dart`, `private_chat_security.dart` | sélecteur emoji (popover 432×448), stickers (dialogue), épinglés (dialogue), transférer, fils, forum, sondages, visionneuse, messages vocaux, commandes, composants bot, lecteurs, embeds, markdown, consentement média, E2EE |
| DM | `user/views/accord_direct_messages*.dart`, `accord_direct_messages_user_search.dart` | **dialogue modal 900×720** (onglets Messages / Friends), conversation, groupes, amis |
| Utilisateur | `user/views/user_panel.dart`, `self_status_button.dart`, `accord_profile_edit.dart`, `accord_account_settings.dart` + `account_settings/*` | panneau bas (52 px), menu statut (PopupMenu), édition profil (dialogue), mot de passe/2FA |
| Paramètres | `settings/views/accord_settings_screen.dart` + `settings_screen/sections.dart`, `keybinds_section.dart`, `privacy_settings_page.dart`, `connections_settings_page.dart`, `settings_backup.dart` | route `/settings` avec AppBar + flèche retour ; barre latérale 232 px si ≥1000 px |
| Vocal | `voice/views/voice_view.dart` + `voice_view/video_grid.dart`, `voice_view/control_bar.dart`, `voice_bar.dart`, `voice_lobby.dart`, `voice_text_panel.dart`, `voice_participants.dart`, `user_volume_menu.dart`, `voice_moderation_menu.dart`, `voice_settings_screen.dart`, `voice_connection_info.dart`, `screen_share_picker.dart`, `stage_view.dart`, `incoming_call_overlay.dart`, `voice_pip_overlay.dart`, `mic_level_meter.dart` | vue d'appel, grille/spotlight, barre de contrôle, panneau « Voice Connected », lobby, chat vocal, participants, volume, modération, paramètres voix (page séparée), infos connexion, sélecteur de partage (desktop), stage, appel entrant, PiP 200×124 |
| Autres | `admin/*` (`/admin` : Spaces, Users, Reports, Settings, AutoMod), `automod/*`, `authentication/*`, `profiles/*` (profils d'appareil + PIN), `onboarding/*`, `updates/*`, `experiences/*` (Arcade), `developer/*` | hors périmètre Discord sauf là où ils apparaissent dans les menus/paramètres |
| Partagé | `shared/components/context_menu.dart` (menu ancré desktop / feuille mobile, 40 px, icône gauche, pas de sous-menu ni de case à cocher), `settings_scaffold.dart`, `dialog_title_bar.dart`, `escape_to_close.dart`, `drawer_swipe_area.dart`, `image_crop_dialog.dart`, `server_unreachable.dart`, `app_banner.dart`, `async_state_views.dart` | |

Faits transverses : aucune `fontFamily` (police système), icônes **Material uniquement**, aucune
constante partagée d'espacement/rayon, thème sombre `#313338 / #2B2D31 / #1E1F22`, accent
`#5865F2`, texte `#DBDEE1` / gris `#949BA4`.

### 2.2 Serveur Rust (`../accordserver/src`)

Routes : admin, applications, audit_log, auth, bans, channels, e2ee, emojis, experiences*,
interactions, invites, members, messages, mutes, polls, profiles, reactions, read_states,
relationships, reports, roles, scheduled_events, settings, **soundboard**, spaces, stickers,
super_reactions, system_messages, users, **voice**, webhooks, welcome_screen.
Vocal : `voice/{livekit,moderation,stage,state}.rs` ; état vocal = `deaf, mute, self_deaf,
self_mute, self_stream, self_video, suppress, request_to_speak_timestamp` (pas de `speaking`,
pas de compteur de spectateurs). Soundboard : modèle sans emoji, `play` diffusé à tout l'espace
via l'événement gateway `soundboard.play`, permissions `use_soundboard` (tous) /
`manage_soundboard` (admin). Permissions `priority_speaker` et `use_vad` jamais appliquées.

## 3. Tableaux de parité

Colonnes : Élément Discord attendu | État actuel dans l'app | Écart précis | Priorité | Statut.
« réf » = capture confirmant l'attendu.

### A. Disposition générale

| Élément Discord attendu | État actuel dans l'app | Écart précis | Prio | Statut |
|---|---|---|---|---|
| Rail 72 px, DM en haut (icône logo, cercle visible), séparateur 32×2 visible, puis serveurs (réf `rail-hover-tooltip`) | `accord_home_rail.dart:104-237` : rail 72, bouton DM `chat_bubble_outline` **fond identique au rail**, séparateur **même couleur que le rail** (invisible) | Cercle DM invisible ; séparateur invisible ; espacement 12 px entre icônes (Discord 8) ; DM ouvre un **dialogue** au lieu de la vue accueil (pas d'état sélectionné) | P1 | ⚠️ |
| Icône ronde → carré arrondi au survol (anim ~150 ms), fond accent au survol si initiales, tooltip **à droite** avec nom (réf `rail-hover-tooltip`) | `_rail_tiles.dart:154-292` : 24→16 px anim 150 ms, fond `primary` | Tooltip Material (au-dessus/dessous) au lieu de bulle à droite ; pas de flèche | P1 | ⚠️ |
| Pilule blanche à gauche : 8 non-lu / 20 survol / 40 sélection (réf `rail-hover-tooltip`) | `_rail_tiles.dart:235-261` : 8/20/40, largeur 8, décalée −16 (≈4 px visibles) | Largeur visible et rayon à vérifier par capture ; absente sur dossiers et bouton DM | P1 | ⚠️ |
| Pastille mention rouge bas-droite avec **anneau découpé** couleur rail, « 99+ » | `_channel_rows.dart:436-460` : rouge `#ED4245`, rayon 10 | Pas d'anneau de découpe ; sur le bouton DM elle est en haut-droite | P2 | ⚠️ |
| Dossiers : tuile teintée, grille 2×2 fermée, **tiroir teinté** ouvert, animation, non-lu/mentions sur le dossier, menu (Mark as read, Folder settings) | `_rail_folders.dart` : grille 2×2, ouverture sans animation, couleur par défaut = couleur rail (invisible) | Pas de tiroir, pas de pilule/badge dossier, menu différent (Rename / Recolor / Delete) | P2 | ⚠️ |
| Bouton « + » (cercle, + vert → fond vert au survol), bouton **Explorer** (boussole, même style), bouton **Télécharger apps** | `_rail_tiles.dart:499-511` + `accord_home_rail.dart:232-236` | « + » sans fond ni survol ; Explorer = `IconButton` hors liste ; bouton télécharger absent (🚫 sans objet web ? à décider : garder un bouton « Télécharger l'app » vers vos builds) | P2 | ⚠️ |
| Colonne salons **240 px fixe**, fond `#2B2D31` | `accord_settings.dart:155` : 220 par défaut, redimensionnable 180-420 | Largeur + poignée de redimensionnement à retirer ou neutraliser à 240 | P1 | ⚠️ |
| En-tête : nom serveur 16 px semibold + chevron qui devient ✕ ; bannière **derrière** l'en-tête ; menu déroulant (réf `menu-server-header-owner`) : Server Boost / Invite to Server, Server Settings, Create Channel, Create Category, Create Event, App Directory / Notification Settings, Privacy Settings / Edit Per-server Profile, Hide Muted Channels ☐ / Copy Server ID (+ Leave Server en rouge si non propriétaire) | `accord_home_channels.dart:139-224, 281-361` : nom 15 px, icône recherche + chevron ; bannière 100 px **sous** l'en-tête | Ordre et entrées du menu différents (Reorder channels, Mark as read, Mute, Copy link, Hide, Leave & delete data, Remove server ; **divider final orphelin**) ; pas d'icônes à gauche ; bannière mal placée ; icône recherche à retirer (Discord : recherche dans l'en-tête central) | P1 | ⚠️ |
| Catégories : chevron qui **tourne**, nom 12 px uppercase, « + » visible **au survol** uniquement, catégorie repliée garde salons non-lus/sélectionné | `_channel_rows.dart:51-130` ; repli cache tout (`accord_home_channels.dart:525`) | Gear + « + » toujours visibles ; pas de rotation ; non-lus cachés au repli | P1 | ⚠️ |
| Salon : icône gris 20 px, nom 16 px gris (blanc si non-lu, blanc sur fond `#404249` rayon 4 si sélectionné), survol fond léger + icônes **Inviter** + **Réglages** (réf `owner-server-text-channel`) | `_channel_rows.dart:247-401` : icône 18 `dirtyWhite`, nom 14, sélection fond `#1E1F22` rayon 8, survol = InkWell | Tailles, couleurs, rayon ; pas d'icône « inviter » au survol ; icône « join » téléphone verte inexistante chez Discord | P1 | ⚠️ |
| Participants sous le salon vocal : avatar 24, nom 14, icônes micro barré / casque barré, icône caméra, **badge LIVE rouge** (réf `voice-connected-sidebar`) ; ligne « Set a channel status » pour l'admin | `voice_participants.dart:181-335` : avatar 22, nom 12, **lettres « M » « D » « V » « S »** à la place des icônes ; tri alphabétique | Icônes manquantes, LIVE manquant, tri (Discord : ordre d'arrivée), pas de statut de salon | P0 (LIVE) / P1 | ❌ |
| Panneau « Voice Connected » (réf `voice-panel-userpanel-zoom`) : icône signal vert + « Voice Connected » (vert) / « salon / serveur » ; à droite **infos connexion** (barres) + **raccrocher** ; dessous 4 boutons pleine largeur : Caméra, Partage d'écran, Activités, Soundboard | `voice_bar.dart:118-267` : point 8 px, texte, icône `network_check`, rangée 32×32 : [PTT] Caméra, Partage, Soundboard, …, Raccrocher | Raccrocher mal placé ; Activités absent (🚫 pas d'activités Discord → bouton **Arcade** à la même place) ; forme/taille des boutons ; pas de barre de niveau micro chez Discord | P1 | ⚠️ |
| Panneau utilisateur 52 px : avatar 32 + statut, nom, sous-ligne « Online » / « In voice » ; boutons Micro (**avec chevron** périphériques), Casque (**avec chevron**), Réglages ; fond rouge translucide quand muet (réf idem) | `user_panel.dart:74-166` | Pas de chevrons ; pas de fond rouge ; sous-ligne = username au lieu de « Online » ; le clic avatar ouvre un PopupMenu au lieu de la **carte compte** (réf `user-panel-popup`) | P1 | ⚠️ |
| En-tête central 48 px : `#` + nom + **sujet** ; à droite : Threads, Cloche, Épinglés, Membres, **champ de recherche** (réf `server-text-channel-members`) ; barre titre au-dessus avec Inbox + Aide | `message_pane.dart:722-851` : icône + nom ; Épinglés + Cloche | Sujet absent ; Threads, Membres, Recherche, Inbox, Aide absents ; l'ordre doit être Threads · Cloche · Pin · Membres · Recherche | P1 | ⚠️ |
| Liste membres 240 px : groupes « RÔLE — N », **« Online — N »**, « Offline — N », ligne 42 px, avatar 32 + statut, nom 16 en couleur de rôle, sous-ligne statut/activité, **couronne** propriétaire, hors-ligne à 30 % (réf `server-text-channel-members`) | `accord_member_list.dart` : groupe sans rôle nommé **« Members »**, nom 14, pas de couronne, pas de sous-ligne, hors-ligne 50 % | Libellé, tailles, couronne, sous-ligne, opacité | P1 | ⚠️ |
| Masquage liste membres : bouton d'en-tête, mémorisé | Ctrl+U seulement (`home_shortcuts.dart:162`) | Bouton absent | P1 | ⚠️ |
| Points de rupture : liste membres auto-masquée sous ~1200 px(à confirmer), colonne salons conservée jusqu'à ~ 940 px(à confirmer) | `home_layout.dart` : membres 920, tiroir sous 680 | À confirmer par capture 13 | P2 | ⚠️ |
| Police : gg sans (propriétaire) → équivalent libre proche ; icônes : set libre proche | Police système, Material Icons | Choisir une police libre (ex. Noto Sans / Inter) et un set d'icônes libre proche (Phosphor / Lucide) ; appliquer partout | P1 | ❌ |
| Bande d'onglets de salons | `accord_home_tabs.dart` | N'existe pas chez Discord : désactiver par défaut / retirer | P2 | ⚠️ |

### B. Messages

| Élément Discord attendu | État actuel dans l'app | Écart précis | Prio | Statut |
|---|---|---|---|---|
| Regroupement 7 min même auteur, rompu par séparateur de jour / NEW / réponse ; heure `HH:MM` au survol dans la gouttière ; en-tête « Nom · Today at 14:32 » / « Yesterday at » / `dd/mm/yyyy HH:MM` | `message_pane.dart:1039-1055`, `message_row_actions.dart:76-111`, `message_time.dart` | Jour/NEW ne rompent pas le groupe ; « Today at » manquant ; icône pin avant le nom (n'existe pas) ; mode compact non conforme | P1 | ⚠️ |
| Barre de survol (réf `message-hover-actionbar`, `-own`) : 3 **emojis rapides**, Réagir, [Modifier si propre], Répondre/Transférer, « … » ; flottante en haut-droite du message | `message_row_actions.dart:117-194` : Réagir, Répondre, Fil, « … » **inline en fin de ligne** | Position, emojis rapides, crayon, ordre ; « … » = PopupMenu réduit | P1 | ⚠️ |
| Clic droit message (réf `menu-message-own`) : [4 emojis] Add Reaction › / Edit Message, Reply, Forward, Create Thread / Copy Text, Pin Message, Bookmark, Create Reminder ›, Apps ›, Mark Unread, Copy Message Link, Speak Message / Delete Message (rouge) / Copy Message ID ; icônes à gauche ; autre auteur : Add Reaction › / Reply / Bookmark, Reminder, Apps, Mark Unread, Copy Link / Report (rouge) / Copy ID | `message_row_handlers.dart:356-472` : 16 entrées, ordre différent, 1 seul séparateur | Réordonner, ajouter emojis rapides + Copy Message ID ; retirer Super reaction du menu principal (Discord : dans le sous-menu réactions) ; Bookmark/Reminder/Apps/Speak = 🚫 (pas de backend) → omis | P1 | ⚠️ |
| Réponse : barre « Replying to X » avec @ON/OFF ; aperçu **cliquable** (avatar + nom + texte) au-dessus du message | `message_row_parts.dart:114-173`, `composer_view.dart:88-113` | Aperçu non cliquable, sans avatar ; pas de bascule mention | P1 | ⚠️ |
| Réactions : pilules, **tooltip des réacteurs au survol**, pilule « + » ajouter | `reactions.dart` | Pas de tooltip, pas de « + » ; réacteurs via dialogue | P1 | ⚠️ |
| Édition ↑ ; éditeur inline avec « escape to cancel • enter to save » ; « (edited) » après le texte (aussi sur messages groupés) avec tooltip date | `composer.dart:143`, `message_row_editing.dart` : boutons Cancel/Save ; « (edited) » dans l'en-tête seulement | Hint texte, position (edited), absent sur groupés, vide → proposer suppression | P1 | ⚠️ |
| Suppression : dialogue aperçu + Shift+clic sans confirmation ; Pin avec confirmation | `message_row_handlers.dart:119-236` conforme ; pin sans confirmation | Pin : ajouter confirmation (à confirmer visuellement, capture 11) | P2 | ⚠️ |
| Markdown : gras, italique, barré (couleur texte), souligné, spoiler (markdown imbriqué, re-masquable), `>` et **`>>>`**, code inline (boîte 4 px), blocs avec coloration, `#`/`##`/`###` seulement (24/20/16), `-#`, listes, liens masqués + **dialogue « lien externe »**, `<t:>`, pilles mentions | `accord_message_markup.dart`, `markdown_viewer` | Barré **rouge** ; `>>>` absent ; citation gris + texte gris ; h4-h6/tables/`==` activés (à retirer) ; mentions texte `@handle` sans état survol ; pas de dialogue lien | P1 | ⚠️ |
| Embeds OpenGraph côté client/serveur, images cliquables dans embeds ; visionneuse (zoom, « Open in Browser », carrousel) ; carte fichier (icône, nom, taille, télécharger) | `accord_embed_box.dart`, `image_lightbox.dart`, `message_row_parts.dart:220` | Embed image non cliquable ; fichiers = texte `📎 nom` ; visionneuse sans carrousel | P1 | ⚠️ |
| Glisser-déposer : **overlay plein panneau** « Upload to #salon » ; coller image ; chips avec **miniature**, spoiler, renommer ; progression d'upload | `composer_view.dart:68`, `attachments.dart:126` | Drop limité au composeur ; chips sans miniature ; pas de progression | P1 | ⚠️ |
| « X is typing… » sous le composeur avec 3 points animés, 1/2/3 noms puis « Several people » | `message_pane.dart:1059-1125` : au-dessus, sans animation, « Several » dès 3 | Position, animation, seuil | P2 | ⚠️ |
| Séparateur « New Messages » rouge + barre supérieure « N new messages since … · Mark as read » ; bouton « Jump to present » | `dividers.dart:118` ; barre et bouton absents | Ajouter barre + bouton | P1 | ⚠️ |
| Surlignage mention : fond jaune/or + barre gauche or | `message_row.dart:339-351` : couleur accent | Couleur | P1 | ⚠️ |
| Sélecteur **unifié** GIF / Stickers / Emoji en popover 498×498 ancré au composeur (réf `emoji-picker`, `gif-picker`, `sticker-picker`), emojis de **tous** les serveurs, fréquents, tons de peau, aperçu bas | `emoji_picker.dart` (432×448, espace courant), `stickers.dart` (dialogue), GIF absent | Unifier en 3 onglets ; GIF = 🚫 sans fournisseur (Tenor/Klipy propriétaires) → onglet GIF avec **Favoris + upload GIF local** ; emojis multi-serveurs | P1 | ⚠️ |
| Composeur (réf `server-text-channel-members`) : « + » à gauche avec menu Upload a File / Create Thread / Create Poll / Use Apps (réf `composer-attach-menu`) ; droite : Gift, GIF, Sticker, Emoji, Apps ; **pas de bouton Envoyer** ; `#salon` autocomplete ; limite 2000 avec compteur ; état sans permission | `composer_view.dart:232-350` | « + » ouvre directement le picker ; Poll séparé ; Envoyer + micro visibles ; `#` absent ; pas de compteur ; pas d'état « no permission » ; Gift = 🚫 → omis | P1 | ⚠️ |
| Fils : panneau latéral complet (messages riches, composeur complet), popover Threads d'en-tête (réf `threads-popover`) | `thread_view.dart` | Réponses sans pièces jointes/réactions ; pas de liste des fils | P2 | ⚠️ |
| Épinglés : **popover** ancré sous l'icône (réf `pinned-popover`), messages rendus | `pinned_messages.dart` : dialogue 460×560 | Convertir en popover ; rendu markdown | P2 | ⚠️ |
| Recherche : champ dans l'en-tête + popover filtres from/in/has/mentions/more (réf `search-filters`), résultats en **panneau droit** | `accord_search.dart` : dialogue, filtres from/in/before/after/pinned | Déplacer dans l'en-tête ; `has:`/`mentions:` ; panneau droit | P2 | ⚠️ |
| Inbox (Unread / Mentions) (réf `inbox-popover`) | absent | Créer popover Inbox (Unread + Mentions ; Bookmarks/Reminders 🚫 omis) | P2 | ❌ |
| DM : vue accueil à part entière (réf `home-friends`) : colonne « Find or start a conversation », Friends / Nitro / Shop / Quests, « Direct Messages + », liste ; centre : onglets Online / All / Pending / Blocked / **Add Friend** ; droite « Active Now » | `accord_direct_messages*.dart` : **dialogue modal** | Refaire en vue plein écran ; Nitro/Shop/Quests 🚫 → omis ; onglets amis ; Active Now (afficher les amis en vocal) | P1 | ⚠️ |
| Ligne « End-to-end encrypted » sous chaque message DM | `message_row.dart:395-403` | N'existe pas chez Discord → remplacer par icône cadenas d'en-tête uniquement | P2 | ⚠️ |

### C. Vocal et vidéo

| Élément Discord attendu | État actuel dans l'app | Écart précis | Prio | Statut |
|---|---|---|---|---|
| Rejoindre d'un clic (desktop) ; sons originaux connexion/déconnexion | `_channel_rows.dart:181-188`, `assets/sfx` (synthétisés) | Conforme sur le principe ; **déconnexion forcée sans son** ; à vérifier : le clic ouvre aussi la vue d'appel (réf `voice-connected-sidebar` : Discord reste sur le salon texte courant et affiche la vue d'appel au clic suivant) | P1 | ⚠️ |
| Couper le son (deafen) **coupe aussi le micro** | `voice.dart:368-379` : micro reste actif | Bug fonctionnel | P1 | ❌ |
| Vue d'appel (réf `call-view-idle`) : fond uni sombre, tuiles 16:9 **adaptées au viewport et centrées**, fond de tuile = couleur de l'utilisateur / gris clair, avatar centré 80, nom bas-gauche en pilule avec icône micro barré, « … » bas-droit au survol ; panneau **« Invite to Voice / Choose Activity »** quand on est seul | `video_grid.dart:393-420` : GridView colonnes fixes, 16:10, scroll, fond `foreground`, avatar 56, icône rouge | Algorithme de grille, tailles, fond, icônes, panneau seul (Activity = Arcade) | P1 | ⚠️ |
| Anneau vert parlant (bordure extérieure arrondie), icônes micro/casque barrés sur tuile (distinctes) | `video_grid.dart:464-468, 540-543` : bordure 2 px, une seule icône | Icônes distinctes selon mute/deaf/server ; à confirmer visuellement (capture 1) | P1 | ⚠️ |
| Barre de contrôle (réf `call-view-controlbar`), centrée en bas, groupe gauche « inviter », centre : [Micro + chevron] [Caméra + chevron] · [Partage d'écran] [Activités] [Soundboard] [« … »] · [Raccrocher rouge large] ; droite : Pop-out, Plein écran ; en-tête : icône + nom, bouton chat à droite | `control_bar.dart:50-137` : Micro, Casque, [stage], Caméra, Partage, Réglages, Raccrocher (cercles identiques) | Réordonner, formes (pilules groupées), chevrons, Soundboard et Activités (Arcade) absents, Casque et Réglages à retirer de la barre, Pop-out absent | P1 | ⚠️ |
| Clic droit participant (réf `menu-voice-participant-sidebar`, `menu-voice-tile`) : Profile, Mention [Message, Call, Add Note] / Mute ☑, Deafen ☐, **User Volume** slider, Preview Camera (tuile), Edit Per-server Profile, Apps › / Pop Out User, Show Non-Video Participants ☑ (tuile) / Open in Mod View, Server Mute ☐, Server Deafen ☐ (rouges) / Copy User ID | `user_volume_menu.dart` : nom, slider, Mute for me, Reset, puis modération | Entrées manquantes (Profile, Mention, Message, Copy ID, Pop Out), cases à cocher, ordre ; menu générique sans support des cases/sous-menus | P1 | ⚠️ |
| Clic simple tuile = focus, double-clic = plein écran, bande des autres en bas, plein écran (bouton + Échap), **pop-out** (desktop : fenêtre ; web : Picture-in-Picture), masquer/afficher chat | `video_grid.dart` : double-tap = spotlight ; bande 110 px carrée ; deux implémentations plein écran (route DM / en place) ; pas de pop-out | Unifier le plein écran (supprimer l'ancienne route), ajouter clic/double-clic Discord, bande 16:9 ; pop-out desktop via fenêtre secondaire (à évaluer : `desktop_multi_window`) sinon 🚫 → PiP ; web : Document PiP | P1 | ⚠️ |
| Panneau utilisateur : micro/casque rouges avec fond rouge translucide, chevron périphériques | voir A | | P1 | ⚠️ |
| Appel entrant, appels DM inline en haut de la conversation | `incoming_call_overlay.dart` ; DM = route plein écran | Appel DM rendu **dans** la conversation (en haut) ; à confirmer (capture) | P2 | ⚠️ |
| Stage : disposition dédiée | `stage_view.dart` | Hors périmètre immédiat ; à confirmer si utilisé | P3 | ⚠️ |

### D. Partage d'écran / Live (PRIORITÉ HAUTE)

Lot livré le 2026-11-03 (commit du lot, voir §6). « réf » = capture Discord ; « app » = capture
de l'app (`docs/discord-ref/app-*.jpg`, build web local, même viewport 1568×711).

| Élément Discord attendu | État actuel dans l'app | Écart précis | Prio | Statut |
|---|---|---|---|---|
| Bouton partage dans le panneau vocal **et** la barre d'appel ; en direct : bouton vert, **menu** Stop Streaming (rouge) / Change Stream (réf `stream-share-button-menu`, `stream-controlbar-chevron-menu`) | `voice_bar.dart` (bouton vert plein + menu), `control_bar.dart` (bouton vert + chevron attaché ouvrant le même menu) ; app `app-stream-share-button-menu` | Aucun sur le contenu ; « Report Problem » omis (🚫) ; forme des pilules de la barre = lot C | P0 | ✅ |
| Carte **« Go Live »** au-dessus de « Voice Connected » (icône jaune, titre, bouton d'arrêt) ; panneau utilisateur « Sharing their screen » (réf `stream-own-started`) | `_GoLiveCard` + `user_panel.dart` ; app `app-stream-own-started` | Aucun | P0 | ✅ |
| Fenêtre de sélection : **web** = sélecteur natif puis démarrage immédiat, sans étape (constaté sur Discord web) ; **desktop** (réf `official-share-picker-step1/2`) = « Screen Share », onglets Applications / Screens, grille 2 colonnes, Cancel / Go Live ; puis What you're streaming + Change, info son, Streaming channel, Stream quality (préréglage Smoother Video / Better Text Readability, 720 / 1080 / 1440 / SOURCE, 15 / 30 / 60), Back / Go Live | web : démarre dès le sélecteur natif ; desktop : `screen_share_picker.dart` reproduit les deux étapes (structure, libellés, boutons) ; échelle de résolution alignée (`accord_settings.dart`, migration des anciens index) ; vérifié par `screen_share_dialog_test.dart` | Omis (🚫) : onglet Capture Devices, « Notify my friends », Clips, « Hide stream preview », préréglage « Custom » ; pas encore de capture visuelle de l'app sur Windows (widget tests seulement) | P0 | ⚠️ |
| Streamer : aperçu de son propre stream dans la **grille** (pas de focus automatique), pilules « 720P 30FPS » + LIVE en haut à droite, pilule nom + icône écran, « … » au survol → Stop Streaming / Change Stream / Pop Out Stream (réf `stream-own-hover-controlbar`, `stream-own-tile-menu`) | `video_grid.dart` : grille ajustée et centrée, stream avant la tuile de son auteur, badges, « … » au survol, menu identique ; `changeScreenShareSource` / `updateScreenShareQuality` republient sans couper ; app `app-stream-own-started`, `app-stream-own-tile-menu` | « More Options › » omis (sous-menu non capturé) ; mobile : carte « You're sharing » conservée | P0 | ✅ |
| Badge **LIVE** rouge en bout de ligne dans la liste du salon ; survol = carte (LIVE, aperçu, bouton **Watch Stream** / **You're Streaming!**, « PROTIP: Double click user to watch ») ; double-clic sur la ligne = regarder (réf `stream-live-badge-hover`, `official-watch-stream-card`) | `voice_participants.dart` : `LiveBadge` + `_StreamCard` (OverlayPortal au survol ; touch = tap sur le badge), PROTIP et double-clic ; app `app-stream-live-badge-hover` | Aperçu = avatar sur fond noir (🚫 miniature, voir §4) ; la ligne d'activité (« Playing for 33 minutes ») n'existe pas (🚫 pas de détection de jeu) | P0 | ✅ |
| Tuile stream non regardé : LIVE + bouton « Watch Stream » ; vidéo reçue **après** clic | `_LiveCard` ; `autoSubscribe: false` + abonnement explicite micro/caméra, stream seulement au clic ; `dynacast` | Visuel à confirmer avec un second participant (capture 5) | P0 | ⚠️ |
| En regardant (réf `official-watching-stream-focus`, `official-watched-stream-menu`) : focus du stream regardé, bande 16:9 centrée, chevron « Hide Members / Show Members » qui replie (focus bord à bord + vignette), menu du stream = Stop Watching / Mute ☐ / Stream Volume (slider), plein écran (bouton + double-clic + Échap) | `_SpotlightLayout` ; clic = focus, double-clic = plein écran ; « … » d'un stream regardé → `showUserVolumeMenu(stream: true, onStopWatching, onPopOut)` : Stop Watching, slider Stream Volume, case Mute, Pop Out (web) ; app `app-stream-own-focused`, `app-stream-focus-strip-collapsed`, `app-stream-own-fullscreen` | Compteur de spectateurs (pilule œil, `stream_watching`) : Discord ne l'affiche que dans l'overlay jeu (icône œil à côté du spectateur) — à confirmer sur la tuile ; « Show Non-Video Participants » et « Report Problem » omis ; capture app d'un stream **distant** toujours impossible sans second compte | P0 | ⚠️ |
| Plusieurs streams : tuiles LIVE séparées, bascule par clic, un seul en focus | tuiles séparées, bascule au clic simple | À confirmer (capture 6) | P0 | ⚠️ |
| Une seule implémentation « regarder » et **un seul plein écran** | `_LiveCard` ; ancienne route plein écran supprimée (`showFullScreenVoice`), appels DM rendus dans la conversation (`MessagePane.topPanel`), PiP et appel entrant migrés | Aucun | P0 | ✅ |
| Pop-out (réf `stream-popped-out-main`) | web : Picture-in-Picture natif (bouton de la barre + menus) ; desktop/mobile : 🚫 (voir §4) | Fenêtre séparée impossible hors web | P0 | 🚫 |
| Son du partage (desktop) | `captureScreenAudio` est « browser only » dans flutter_webrtc ; réglage conservé pour le web, texte explicite | — | P0 | 🚫 |

### E. Soundboard

| Élément Discord attendu | État actuel dans l'app | Écart précis | Prio | Statut |
|---|---|---|---|---|
| Bouton dans le panneau vocal (4ᵉ) **et** dans la barre d'appel (après Activités) | panneau vocal oui ; barre d'appel **non** | Ajouter dans la barre | P1 | ⚠️ |
| **Popover** ancré au bouton (pas un dialogue) : recherche, onglets Favoris / ce serveur / autres serveurs, grille de cartes **emoji + nom**, bouton aperçu au survol, slider volume en bas, lien « add sound » | `accord_soundboard.dart` : dialogue 480×560, grille 3 col., sans emoji, sans favoris, un seul serveur | Convertir en popover ; **emoji** = ajouter champ côté serveur (`models/soundboard.rs`) + SDK + UI ; favoris (local) ; autres serveurs (lister les espaces connectés) | P1 | ⚠️ |
| Volume du soundboard par utilisateur (Paramètres Voix › Soundboard, réf `settings-voice-6-soundboard`) + « Entrance sounds » | slider global dans le dialogue + `soundboardVolume` | Déplacer dans Paramètres ; sons d'entrée = P3 | P2 | ⚠️ |
| Ajout par membres autorisés (permission « Create Expressions » distincte de « Manage »), upload avec nom + emoji + volume + découpage 5 s | `manage_soundboard` seul ; upload brut | Ajouter permission `create_soundboard` côté serveur ; dialogue d'upload (nom, emoji, volume) ; découpage 🚫 (pas d'encodeur) → limite de durée serveur | P2 | ⚠️ |
| Indication sur l'avatar de qui joue (pulsation + emoji) | aucune | Utiliser l'événement `soundboard.play` reçu pour animer la ligne/tuile | P1 | ❌ |
| Transport : OK (événement gateway + lecture locale) ; sécurité serveur : vérification `space_id` manquante sur les requêtes par `sound_id` | `accordserver/src/db/soundboard.rs` | Corriger (hors UI, mais à faire dans le lot E) | P1 | ⚠️ |

### F. Menus, raccourcis, interactions

| Élément Discord attendu | État actuel dans l'app | Écart précis | Prio | Statut |
|---|---|---|---|---|
| Widget de menu : largeur ~190-220, item 32 px, texte 14 medium, icône **à droite** (menus salon/serveur) ou à gauche (message), séparateurs 1 px, items rouges avec **fond rouge au survol**, cases à cocher, sous-menus avec chevron, sous-titre (« All Messages ») | `context_menu.dart` : 40 px, icône gauche, pas de case/sous-menu/sous-titre ; 3 menus contournent le widget (membres, onglets, volume) | Réécrire le widget (support cases, radio, sous-menus, sous-titres, danger hover) et y migrer tous les menus | P1 | ⚠️ |
| Icône serveur (réf `menu-server-icon-owner`) : Mark as Read / Invite to Server / Mute Server ›, Notification Settings › (sous-titre), Hide Muted Channels ☐ / Server Settings ›, Privacy Settings, Edit Per-server Profile / Create Channel, Create Category, Create Event / Move to… › / Leave Server (rouge, non proprio) / Copy Server ID | `accord_home_rail.dart:368-410` | Ordre et entrées (voir A) ; Privacy/Per-server profile 🚫 si pas de backend → omis ou « Edit nickname » | P1 | ⚠️ |
| Salon texte (réf `menu-text-channel-owner`) : Mark as Read / ★ Add to Favourites / Invite to Channel, Pin Channel to Top, Copy Link / Mute Channel ›, Notification Settings › / Move to… › / Edit Channel, Duplicate Channel, Create Text Channel, Delete Channel (rouge) / Copy Channel ID | `channel_context_menu.dart:38-128` : Mark as read (si non-lu), Mute, Edit, Delete | Entrées manquantes ; Favourites/Pin to top = P3 | P1 | ⚠️ |
| Salon vocal (réf `menu-voice-channel-owner`) : idem + Invite to Voice, **Open Chat**, Hide Names ☐, Create Voice Channel | idem + Join/Disconnect | Join Voice n'existe pas dans le menu Discord (clic simple) | P1 | ⚠️ |
| Catégorie (réf `menu-category-owner`) : Mark as Read / Collapse Category ☐, Collapse All Categories / Mute Category ›, Notification Settings › / Move to… › / Edit Category, Delete Category / Copy Category ID | Expand/Collapse, Create channel here, Edit, Delete | Entrées manquantes | P1 | ⚠️ |
| Membre (réf `menu-member`) : Profile, Mention, Message, Start a Call, Add Note / Apps ›, Invite to Server ›, Add Friend, Ignore, Block (rouge) / Copy User ID ; + modération (Roles ›, Timeout, Kick, Ban) pour les modérateurs (à confirmer, capture) | `accord_member_list.dart:360-406` : View Profile, DM, Copy ID, Copy Username | Réécrire ; modération déplacée depuis le popout vers le menu | P1 | ⚠️ |
| Clic droit avatar/nom d'un message = menu membre | désactivé dans les espaces (`accord_home.dart:680`) | Activer | P1 | ❌ |
| Raccourcis : Ctrl+K ✓, Ctrl+Shift+M ✓, Ctrl+Shift+D ✓, Alt+↑/↓ ✓, Ctrl+Alt+↑/↓ ✓, Ctrl+/ ✓, Ctrl+E ✓, ↑ ✓ ; **manquants** : Échap = marquer lu / fermer, Shift+Échap = serveur lu, Alt+Shift+↑/↓ (non-lus), Ctrl+Alt+Shift+↑/↓ (mentions), Shift+PgUp/PgDn, Ctrl+F, Ctrl+I, Ctrl+P, Ctrl+Shift+U (upload), Ctrl+Shift+I (inbox), Ctrl+B/I/U (format), Ctrl+Enter | `home_shortcuts.dart:115-180` | Ajouter les manquants ; dialogue Ctrl+/ à refaire en grille de touches (à confirmer, capture 12) | P2 | ⚠️ |
| Popout profil (réf `profile-popout`) : bannière (couleur/image) avec **avatar à cheval**, boutons « ajouter ami » + « … » en haut-droite, nom, @handle + badges, « mutual friends/servers », champ **« Message @X »** en bas ; onglets About me / rôles ; carte propre compte (réf `user-panel-popup`) : Edit Profile, statut ›, Switch Accounts, Copy User ID | `accord_member_popout.dart` : bande 56 px, en-tête, extras, rôles, modération, boutons texte | Refaire la carte ; modération → menu contextuel ; champ message ; carte compte propre | P1 | ⚠️ |
| Statut (réf `status-picker`) : Online / Idle › / Do Not Disturb › (sous-titre) / Invisible › + durées ; statut personnalisé avec emoji + « Clear after » | `self_status_button.dart` | Sous-menus durée, sous-titres, dialogue statut avec picker emoji | P2 | ⚠️ |
| Quick switcher (réf `quick-switcher`) : modale en haut, « Search for servers, channels or DMs », résultats serveurs/salons/DM/utilisateurs, préfixes @ # ! * $, Protip | `quick_switcher.dart` : salons seulement | Étendre les sources, préfixes, style | P2 | ⚠️ |

### G. Paramètres

| Élément Discord attendu | État actuel dans l'app | Écart précis | Prio | Statut |
|---|---|---|---|---|
| Paramètres utilisateur (réf `settings-*`) : **modale centrée** (2026) avec barre latérale (avatar + Edit Profiles, Recherche, Account › Account Info / Password & Security / Account Status / Family Centre, Data & Privacy, Messaging Permissions, Notifications ; Billing… ; Experience : Voice & Video, Appearance, Accessibility, System, Language & Time ; Games & Apps ; Developer ; Log Out), bouton ✕ en haut-droite, Échap ferme, sous-sections ancrées | `accord_settings_screen.dart` : route avec AppBar + flèche ; USER SETTINGS / APP SETTINGS / SYSTEM | Refaire le conteneur (modale + ✕), réordonner les catégories sur le modèle Discord 2026, Billing/Family/Nitro 🚫 → omis ; « Text & Images » → intégré à Appearance › Messages/Chat Box (réf `settings-appearance-2`) | P2 | ⚠️ |
| Barre « Careful — you have unsaved changes! » Reset / Save Changes en bas (à confirmer, capture 14) | inexistante | Créer le composant ; l'utiliser dans profil/serveur/rôles/salon | P2 | ❌ |
| Voix & Vidéo (réf `settings-voice-1..6`) : Microphone / Speaker dropdowns côte à côte, volumes, **Mic Test** (bouton + barres), Input Profile (Voice Isolation / Studio / Custom), Input Sensitivity (slider dégradé), Noise Suppression, Echo Cancellation, Push-to-talk, Advanced ; Camera (aperçu + Test Video, Always preview, Camera dropdown) ; Streaming (Show Stream Previews) ; Sounds (liste avec Preview Sound) ; Soundboard (volume, Entrance sounds) ; Advanced | `voice_settings_screen.dart` : page séparée, mic test seulement en vocal, slider manuel non appliqué à la transmission | Intégrer dans la modale ; mic test autonome ; détection de voix réelle (VAD) ou 🚫 → « Automatic » via LiveKit ; aperçu caméra ; PTT : délai de relâche | P2 | ⚠️ |
| Apparence (réf `settings-appearance-1`) : Same as Device Theme, Default Themes (clair/sombre/…), Messages (cozy/compact + aperçu), Chat Box, Search, Streamer Mode | ChoiceChips thèmes, Compact mode switch, UI scale dans Accessibility | Aperçu de message, zoom/échelle de police, « sync with device » | P2 | ⚠️ |
| Notifications (réf `settings-notifications`) : Enable Desktop Notifications, « Notify me when… » toggles, Sounds (liste) | `sections.dart:285-386` | Structure et libellés ; sons par événement déjà présents | P2 | ⚠️ |
| Paramètres serveur (réf `server-settings-owner-sidebar-top/bottom`) : **plein écran**, ✕ ESC, menu latéral : Server Profile, Server Tag, Engagement, Boost Perks / Expression : Emoji, Stickers, Soundboard / People : Members, Roles, Invites, Access / Apps : Integrations, App Directory / Moderation : Safety Setup, Audit Log, Bans, AutoMod / Enable Community / Server Template, Delete Server (rouge, icône corbeille) | `accord_space_settings*.dart` : page défilante 2 colonnes avec bouton « Save settings » | Refaire en plein écran + menu latéral ; mapper : Server Profile (overview), Emoji, Stickers, Soundboard, Members, Roles, Invites, Access (vérification/NSFW/guest), Integrations (webhooks), Audit Log, Bans, AutoMod, Delete Server ; Tag/Engagement/Boost/Community/Template/App Directory 🚫 → omis | P2 | ⚠️ |
| Rôles (réf `server-settings-roles`) : page avec « Create Role », « Default permissions @everyone › », éditeur onglets Display / Permissions / Manage Members | dialogue 720×560 | Intégrer dans les paramètres serveur, onglets | P2 | ⚠️ |

### H. Notifications et non-lus

| Élément Discord attendu | État actuel dans l'app | Écart précis | Prio | Statut |
|---|---|---|---|---|
| Salon lu = gris `#80848E`, non-lu = blanc + **pilule gauche** (bord de la colonne), salon muet **atténué** (30 %) et sans pilule | `_channel_rows.dart:328-369` : lu `#DBDEE1`, non-lu blanc + **point à droite** ; muet non atténué (mute serveur ignoré par la ligne) | Couleurs, pilule gauche, atténuation muet | P1 | ⚠️ |
| Pastilles mentions par salon/serveur/DM, badge barre des tâches | présents | Vérifier taille/position par capture | P1 | ⚠️ |
| Notification Settings › (serveur/catégorie/salon) : Use default / All Messages / Only @mentions / Nothing (réf `channel-notification-popover`) + Mute › durées 15 min / 1 h / 3 h / 8 h / 24 h / until I turn it back on ; « Suppress @everyone », « Mobile push » | cloche salon : 4 niveaux + mute on/off ; serveur : mute on/off seulement | Niveaux serveur/catégorie, **durées** de mute, popover de cloche identique à la référence | P2 | ⚠️ |
| Son de notification, notifications desktop (déjà), **marquer comme lu avec Échap**, barre « new messages since », Inbox | sons/desktop OK ; Échap, barre, Inbox absents | voir B/F | P2 | ⚠️ |
| Badge « NEW » sur un salon créé récemment | absent | P3 | P3 | ❌ |

## 4. 🚫 Impossibilités connues et alternatives retenues

| Point | Raison | Alternative la plus proche |
|---|---|---|
| Miniature d'aperçu du stream dans la carte « Streaming Now » | Le serveur Accord ne génère pas d'aperçu ; LiveKit n'envoie la vidéo qu'aux abonnés ; et un second rendu d'une piste déjà affichée plante le moteur sur Windows | Carte identique (titre, LIVE, bouton Watch Stream / You're Streaming!) avec l'avatar du streamer sur fond noir à la place de la miniature |
| Sélecteur de partage avec miniatures sur **web** | Le navigateur impose `getDisplayMedia` et son propre sélecteur. Constaté le 2026-11-03 : Discord web n'affiche **aucune** étape (ni avant ni après le sélecteur natif), le stream démarre dès la validation ; la qualité (720p 30fps) vient des réglages | Même comportement : sélecteur natif puis démarrage, qualité depuis Paramètres › Voix & Vidéo ; le client desktop garde la fenêtre à deux étapes (Applications / Screens → qualité → Go Live) |
| « Pop Out Stream » / « Pop Out » (fenêtre séparée) sur desktop | Une seconde fenêtre Flutter a son propre moteur et ne peut pas afficher une texture WebRTC du moteur principal | Web : Picture-in-Picture natif du navigateur sur la vidéo du stream (menu « … » et bouton de la barre). Desktop/mobile : pas de bouton ; l'aperçu flottant intégré (PiP) suit déjà l'appel quand on change de salon |
| Son du partage (desktop) | `flutter_webrtc` ne capture le son d'écran que dans un navigateur (`captureScreenAudio` : « browser only ») | Réglage « Share audio » conservé pour le web ; le texte du réglage dit que le client desktop partage la vidéo seule |
| « Report Problem » dans le menu du stream, « More Options › » de la tuile | Télémétrie Discord propriétaire ; sous-menu non capturé | Omis |
| GIF (Tenor/Klipy), Nitro, Shop, Quests, Gift, Boost, Bookmarks, Reminders, Speak Message, Apps, App Directory, Family Centre, Billing | Services propriétaires sans backend Accord | Omis (pas de bouton factice) ; onglet GIF = favoris + GIF uploadés |
| « Activities » | Discord Activities propriétaires | Bouton **Arcade** au même emplacement (panneau vocal + barre d'appel) |
| Découpage audio du soundboard à l'upload | Pas d'encodeur côté client web | Limite de durée côté serveur + message d'erreur |
| Police gg sans, icônes Discord | Propriétaires | Police libre proche (à valider : Inter / Noto Sans) + set d'icônes libre proche (à valider : Phosphor ou Lucide) |
| Sons Discord | Propriétaires | Sons synthétisés existants (`tool/make_sfx.py`) retravaillés pour être proches en caractère |

## 5. Ordre des lots proposé (à valider)

1. **Lot D — Partage d'écran / Live** (P0) : badge LIVE + popover, sélecteur 2 étapes (desktop + web), aperçu/changement à chaud, abonnement sélectif réel, spectateurs (serveur + client), plein écran unique (suppression de l'ancienne route), pop-out.
2. **Lot A — Disposition** : police + icônes libres, rail, colonne salons 240, en-tête central (Threads/Cloche/Pin/Membres/Recherche), liste des membres, panneau vocal, panneau utilisateur, points de rupture.
3. **Lot C — Vocal/vidéo** : vue d'appel (grille, tuiles, barre de contrôle ordonnée, panneau « seul »), menus participant, deafen = mute, focus/plein écran/pop-out.
4. **Lot B — Messages** : barre de survol, menu contextuel, réponses, réactions, édition, markdown, uploads, typing, NEW/jump, sélecteur unifié, composeur, DM en vue accueil.
5. **Lot F — Menus + raccourcis + profils** : widget de menu, tous les menus contextuels, raccourcis manquants, popout, statut, quick switcher.
6. **Lot E — Soundboard** : popover, emoji (serveur), favoris, barre d'appel, indicateur avatar, permission création, correctif `space_id`.
7. **Lot G — Paramètres** : modale utilisateur, plein écran serveur, barre « unsaved changes », Voix & Vidéo complet.
8. **Lot H — Notifications/non-lus** : couleurs, pilules gauche, muet atténué, durées de mute, Échap, Inbox.
9. **Android** : après réception des captures mobiles.

## 6. Journal des lots

| Date | Lot | Commit | Captures avant/après | Écarts restants | À confirmer |
|---|---|---|---|---|---|
| 2026-11-03 | Étape 0 — audit | (ce fichier) | — | tout | voir §1.1 |
| 2026-11-03 | Lot D — partage d'écran / Live | `a8c987b6` (serveur `ecdfa2c`) | `desktop-stream-*` (11) / `app-stream-*` (8) | sélecteur desktop (capture Discord desktop à fournir), stream distant (second compte requis : spectateurs, Watch Stream, 2 streams) | §1.1 points 2, 4 (autre streamer), 5, 6 |
| 2026-11-03 | Lot D — complément d'après les images officielles Discord | (commit suivant) | `official-*` (8), `desktop-stream-others-channel-list` | sélecteur desktop aligné sur les deux étapes officielles (tests widget, pas de capture app Windows), menu du stream regardé = Stop Watching / Mute / Stream Volume, carte PROTIP + double-clic ; reste : tuile « Watch Stream » et compteur côté app (second compte), capture visuelle du sélecteur sur Windows | §1.1 points 5, 6 |

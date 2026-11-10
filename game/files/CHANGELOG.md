# Balatro Overhaul changelog

What each version brings to players. The game shows this file in About > Changelog and in the What's new window on the title screen, in English, French or Spanish.

Format: `## version | date`, then one `### en`, `### fr` and `### es` block per version (the text after the language code is the version's title). Lines starting with `+ ` are the big lines: they come first, and the first five are the ones the What's new window shows. Lines starting with `- ` are the rest. A line can start with `{card_key}` (for example `{j_hologram}`) to show that card as a small icon, then a short title in square brackets (for example `[Random deck]`), shown in gold above the line. The game reads its own copy, assets/CHANGELOG.md; keep tools/release/CHANGELOG.md the same.

## 2.0.3 | 2026-11-10

### en Overhaul 2.0.3 (pre-release)
+ [Multiplayer] The ONLINE / OFFLINE label in the menus now checks the server for real. It used to say OFFLINE everywhere outside a lobby or a match, even when the servers were up.

### fr Overhaul 2.0.3 (préversion)
+ [Multijoueur] L'indicateur EN LIGNE / HORS LIGNE des menus vérifie maintenant vraiment le serveur. Il affichait HORS LIGNE partout en dehors d'un salon ou d'un match, même quand les serveurs étaient actifs.

### es Overhaul 2.0.3 (versión preliminar)
+ [Multijugador] El indicador EN LÍNEA / SIN CONEXIÓN de los menús ahora comprueba el servidor de verdad. Antes ponía SIN CONEXIÓN fuera de una sala o partida, incluso con los servidores activos.

## 2.0.2 | 2026-11-10

### en Overhaul 2.0.2 (pre-release)
+ [Credits] Steamodded, Balatro-DeckCreator and Cryptid are now credited in the game, and the licence and the third-party notices come with the game and the downloads. The Overhaul's source code is now public under the GPL v3.
+ [Version] The build number now shows next to the version, for example V 2.0.2 (pre-release) b55.
- Removed the Joker Info overlay, at its author's request.

### fr Overhaul 2.0.2 (préversion)
+ [Crédits] Steamodded, Balatro-DeckCreator et Cryptid sont maintenant crédités dans le jeu, et la licence et les mentions des projets tiers sont fournies avec le jeu et les téléchargements. Le code source de l'Overhaul est maintenant public sous GPL v3.
+ [Version] Le numéro de build s'affiche maintenant à côté de la version, par exemple V 2.0.2 (préversion) b55.
- Suppression de l'overlay Info Joker, à la demande de son auteur.

### es Overhaul 2.0.2 (versión preliminar)
+ [Créditos] Steamodded, Balatro-DeckCreator y Cryptid ahora aparecen en los créditos del juego, y la licencia y los avisos de terceros se incluyen con el juego y las descargas. El código fuente del Overhaul ahora es público bajo la GPL v3.
+ [Versión] El número de build ahora se muestra junto a la versión, por ejemplo V 2.0.2 (versión preliminar) b55.
- Se quitó la superposición de Info del Comodín, a petición de su autor.

## 2.0.1 | 2026-11-09

### en Overhaul 2.0.1 (pre-release)
+ [Credits] The multiplayer is based on Balatro Multiplayer by Virtualized and the BMP team. They are now credited in large letters in Credits and in About.
+ [Android] Fixed the black curved area that could cover part of the screen on some phones, such as the Pixel 9 Pro.
+ [Android] The phone app works with any Balatro APK, even when its game files differ a little from the one the Overhaul was made for.
+ [Forge] A joker that gives chips, mult and Xmult when a hand is played now shows a popup for each effect.
+ [PC] The Quit button is back on the Windows main menu.
- Fixed crashes in the Workshop list with long mod names, and with the Reroll Surplus and Reroll Glut vouchers.

### fr Overhaul 2.0.1 (préversion)
+ [Crédits] Le multijoueur est basé sur Balatro Multiplayer de Virtualized et de l'équipe BMP. Ils sont désormais crédités en grand dans Crédits et dans À propos.
+ [Android] Correction de la zone noire courbe qui pouvait cacher une partie de l'écran sur certains téléphones, comme le Pixel 9 Pro.
+ [Android] L'application mobile fonctionne avec n'importe quel APK de Balatro, même si ses fichiers de jeu diffèrent un peu de celui pour lequel l'Overhaul a été fait.
+ [Forge] Un joker qui donne des jetons, du multi et du Xmulti quand une main est jouée affiche maintenant une bulle pour chaque effet.
+ [PC] Le bouton Quitter est de retour dans le menu principal sous Windows.
- Correction de plantages dans la liste de l'Atelier avec des noms de mods longs, et avec les coupons de relance Reroll Surplus et Reroll Glut.

### es Overhaul 2.0.1 (versión preliminar)
+ [Créditos] El multijugador está basado en Balatro Multiplayer de Virtualized y el equipo de BMP. Ahora aparecen con letras grandes en Créditos y en Acerca de.
+ [Android] Corregida la zona negra curva que podía tapar parte de la pantalla en algunos móviles, como el Pixel 9 Pro.
+ [Android] La app del móvil funciona con cualquier APK de Balatro, aunque sus archivos del juego difieran un poco del que se usó para crear el Overhaul.
+ [Forja] Un joker que da fichas, multi y Xmulti al jugar una mano ahora muestra un aviso por cada efecto.
+ [PC] El botón Salir vuelve al menú principal en Windows.
- Corregidos cierres inesperados en la lista del Taller con nombres de mods largos, y con los cupones de tirada Reroll Surplus y Reroll Glut.

## 2.0 | 2026-11-08

### en Overhaul 2.0 (pre-release)
+ {j_ring_master} [Multiplayer] Play online in 1v1 or in parties of up to 8, against friends, random players or bots, casual or ranked. Quick Match, public or private rooms with a 4-letter code, a room browser, and your seat is kept for 15 minutes if you disconnect.
+ {c_chariot} [The Forge] Make your own jokers, tarots, planets, spectrals, vouchers, enhancements, seals, editions, tags, blinds, stakes, decks and booster packs. Draw their art in the pixel editor, use them in your runs and share them online.
+ {c_wheel_of_fortune} [The Casino] A new map with eight places: the Tavern, the Market, the Tailor, the Forge, the Library, the Training Grounds, the Arcade and the Racetrack.
+ {j_golden} [Progression] XP and 100 levels over 7 ranks, daily and weekly quests, Journeys and over 200 achievements. Levels and quests pay Balacoin, which you spend in the Market.
+ {j_hologram} [Hologram] The Overhaul's mascot. Hologram shows you around on first launch and explains each new screen the first time you open it. You can skip or replay the tour. Hologram also sits next to the Ace on the title screen, and two Holograms greet you in the multiplayer menu.
+ [1v1 modes] Rivals: boss blinds are PvP from ante 2. FaceOff: every blind is PvP. Ascension: no PvP, the furthest round wins. Race: first to clear the target ante wins. Switcheroo: after each boss blind you trade runs with your opponent (deck, jokers, money, everything but your lives), after a ready screen and a 3 second countdown.
+ [Party modes] Battle Royale: the lowest scores on each PvP blind lose a life, last one standing wins. Teams: teams of 2 to 4 add up their scores and share their lives. Co-op Raid: everyone scores against one shared boss, with shared lives and a bonus for the top scorer. Race also works with more players.
+ [PvP blinds] Both players play the same blind and the higher score wins. The loser loses a life, and with no lives left the match is lost. Parties have their own blinds: Royale Blind, Team Clash and Raid Boss.
+ [Ranked] Rivals with fixed rules and a deck draft where each player bans 2 of 5 decks. 10 ranks from Stone to TRUE JIMBO, with 3 tiers each. Seasons every three months, with a soft reset and a season badge and sleeve for your peak rank. Ranked XP opens packs of titles, sleeves, card and joker frames, flames, bursts and celebrations.
+ [Daily and Weekly] A multiplayer challenge with rules, a deck and a seed picked by the server, one or two random modifiers, and a leaderboard.
+ [Room settings] The host picks the lives, the ante PvP starts at, the final ante, the deck (or lets each player pick one), the stake, the seed, timers, free timeouts, life steal, a PvP win bonus, comeback money, a hidden enemy score, a shared shop queue, banned cards and any custom run rule. Settings can be saved in 3 preset slots.
+ [Rulesets] Ready-made rules for each mode: Classic, Balanced, Vanilla, Slow burn, Tournament, Scarcity, Sprint, Chaos, Quick duel, Rapid fire, Marathon, Glass cannon, Sudden death, Bloodbath, No carry and Heroic.
+ [Modifiers] Layers the host can stack on any match: three clock speeds, sturdy or fragile Glass cards, Inflation, No interest, Discard tax, Frugal, Spartan, a bigger or tighter shop, Mystery prices, Shared pockets, Unstable score, No red seals, No gambling, Scarcity, Face down cards and Eternal jokers.
+ [Traps] Trap Packs in the shop let you set one of 12 hidden traps on your opponent. For example Tollbooth makes their rerolls pay you, and Bear Trap makes the next joker they buy Rental. Up to 3 traps can wait on one player.
+ [Multiplayer jokers] 20 jokers that only exist in multiplayer, like Truce, Grudge, Mirror Match and High Roller, and jokers made for Ascension, Race, Battle Royale, Teams and Raid. They wear a purple tint and a small MP mark in the corner.
+ [Decks and stakes] Lilac, Seer, Tangerine, Cobalt, Gemini and Random decks. The Random deck gives each hand random Chips and Mult and shuffles prices, card values and packs, with a chaos slider. Three multiplayer stakes: Nova, Eclipse and Eclipse+.
+ [Reworks] Some rulesets change a few base cards: Hanging Chad, Bloodstone, Glass cards, Golden Ticket, Seltzer, Turtle Bean and Ouija. The room and Collection > Reworks show which ones.
+ [Friends and chat] Friends list with online status, invites and Ask to join, private messages, lobby chat that keeps working during the run, 12 emotes, mute, report and block. Chat asks your age once and is for players 13 and over. Duplicate cosmetics can be sent to friends as gifts.
+ [Replays and spectating] Finished matches are saved as replays you can pause, speed up and skip through. Watch public or friends' matches live, or watch the others once you're done with your hands.
+ [Bots and modded rooms] The host can add Easy, Medium or Hard bots. Rooms can use mods (beta): they list their mods and the missing ones install when you join.
+ [4 new stakes] After Gold Stake. Chaos: booster packs offer one fewer choice. Apocalypse: Boss Blinds also debuff a random suit. Oblivion: a random joker is debuffed each blind. Transcendent: every Boss Blind is a finisher. Each one keeps the stakes below it, raises the winning ante by one (10 to 13), and has its own sticker.
+ [Custom runs] Set your own rules in 8 categories: basics, economy, blinds, shop, deck, items, bans and fun. Hands, discards, hand size, slots, money, interest, blind size, shop odds, deck size from 1 to 208 cards, starting jokers and vouchers, banned cards, a number randomizer and more. Save your rules as presets.
+ [Random runs] A random deck and stake, or a Custom random run with random rules you can read before you start.
+ [Daily run] The same seed for everyone each day, with 2 twists, 1 boon and a starting joker. One scored try per day, a streak, and a leaderboard with a Friends tab.
+ [Speedruns] Ante 2, Ante 4 and Any% categories, on a weekly seed or random seeds. A timer with ante splits, personal bests, an online leaderboard and replays of the best runs.
+ [New challenges] 10 new challenges: Bankruptcy, The Gauntlet, Tiny Hands, Heavy Hitter, Glass Cannon, The Collector, Wildcard, Speed Run, The Alchemist and Duality.
+ [Boss Practice] Fight any boss you've met, with the deck and loadout you want, even one taken from a past run. No rewards, and nothing goes into your stats.
+ [Run history] Your last 200 runs with their seed, deck, stake, best hand and final jokers. Play the seed again, or watch a replay of any of your last 50 runs.
+ [Seed Library] Save seeds with their deck and stake, or paste one, and play them later.
+ [Deck Creator] Make your own decks: rules, money, shop odds, exactly which cards are in the deck, starting items and twists. Share them as a text code.
+ [Cheats] Turn them on before a run, then use the Cheats button (you can drag it anywhere) to add jokers, cards, consumables and vouchers, level up hands, change money, hands and slots, or win the blind. A run with cheats gives no progress.
+ [Stats] Solo and multiplayer stats: wins, streaks, best hand, highest ante, time played, results per deck and stake, and your favourite jokers and hands.
+ [Market] Spend Balacoin on packs of cosmetics: Palette, Jester, Sleeve, Shine and Title packs, Jumbo packs, and the Tavern and Legend Crates. Every odd is in the Odds tab, items you don't have are 3 times more likely, duplicates turn back into Balacoin, and Legend Crates give a Legendary at least every 40 cards.
+ [Tailor] Equip your cosmetics: profile icon and its shine, title, colour sets, table felt, card backs in 5 finishes, score flames, celebrations, portraits and Jimbo skins. The Polychromatic palette has its own editor: pick each colour with hue, saturation and brightness and see it live. New legendary palette in the Market: Bubblegum.
+ [Arcade] 10 minigames: High or Low, Joker Memory, Name the Hand, Find the Ace, Blackjack, Whack-a-Joker, Slot Machine, Beat the Blind, Jimbo Run and Jimbo Jam, a rhythm game that can play any song from your Jukebox. Each one keeps your best score, and you can play them while you wait in multiplayer.
+ [Inside the Forge] Joker rules are built from 20 triggers, 23 conditions and 26 effects, with variables. The pixel editor has drawing, shape and selection tools, a soul layer and picture import. Export creations as a .forgemod file, publish them online, or let your whole room play with them.
+ [Quests and achievements] 4 daily quests (one free swap a day), 4 weekly quests, and 24 Journeys with 3 to 5 stages each. Achievements have popups, rarities, and give titles, badges and cosmetics.
+ [Normal and Modded] Two separate games, switched from the title screen. Normal never loads mods, Modded loads yours. Each one has its own 3 profiles, so mods can't touch your main saves.
+ [Mod support] Most Steamodded and Lovely mods work, on Android too. The Mods menu turns them on and off, opens their settings, updates and removes them. A mod .zip in your Downloads folder installs at startup. If a mod crashes the game at startup, the next start turns it off and tells you which one it was.
+ [Workshop] Browse, search and install mods from the Balatro Mod Index without leaving the game. Required mods are installed for you, and each mod says if it works on your platform.
+ {j_hologram} [Bot-latro] Watch our trained bot play. Fair (w15) sees only what you see and wins about 6% of Gold Stake runs, with a win on every deck. The Seer reads the seed. The Stats tab shows the trained bot's results per deck and stake.
+ [Launcher] For Windows, macOS, Linux and Android. It finds your Balatro (Steam, the Xbox app, Flatpak), builds the Overhaul from it, brings in your Balatro progress or starts fresh, backs up your saves and adds shortcuts. On PC it can also make an Android app from your Steam copy. On Android it makes a second app, Balatro Overhaul, that opens straight into the game, updates itself and takes your saves along.
+ [Updates and saves] The game and the launcher tell you when there's an update and install it, and your saves stay. Export all your profiles as one .zip and import them on another device. A backup is made before any import.
+ [Controls] Full controller support with rebinding and slide select, a whole run playable on keyboard with rebinding, touch on PC and phone, a trackpad mode, and a cursor speed setting.
+ [Helpers] Score preview, joker info under each joker, Jimbo commenting on your run, drag to select, total sell value, quick restart, interest guard, safe sell, fast packs, a speed key up to 20x in solo, mute keys, pause when you tab out, and a settings search.
+ [Jukebox] Play your own music instead of the soundtrack. Put mp3, ogg, wav or flac files in the My Music folder, or let the game find them in Downloads.
+ [Display and performance] A performance mode, plus separate options for sharpness, background, card shine, particles and frame rate. Colour filters, an FPS counter, UI size, and Fill the screen on phones in portrait.
+ [Languages] The whole Overhaul is in English, French and Spanish.
- Blue Stake: instead of -1 discard, shop items cost $1 more and rerolls go up by $2. Higher stakes keep it, except Nova and Eclipse.
- Wild Cards can't be debuffed by Boss Blinds.
- Matador gives $2 for each discard used during a Boss Blind.
- Death and the other cards with raised values work above their normal value.
- A blind you already beat can't be played again.
- The title screen has a What's new window, and About has the changelog, credits and a Ko-fi link.
- Crash reports are on by default. They send the error, the version, your platform and your mod list. Turn them off in Settings > Account.

### fr Overhaul 2.0 (préversion)
+ {j_ring_master} [Multijoueur] Jouez en ligne en 1v1 ou en groupe jusqu'à 8, contre des amis, des inconnus ou des bots, en partie libre ou en classé. Partie rapide, salons publics ou privés avec un code à 4 lettres, liste des salons, et votre place est gardée 15 minutes si vous êtes déconnecté.
+ {c_chariot} [La Forge] Créez vos propres jokers, tarots, planètes, spectrales, bons, améliorations, sceaux, éditions, étiquettes, blinds, mises, jeux et paquets. Dessinez-les dans l'éditeur de pixels, utilisez-les dans vos parties et partagez-les en ligne.
+ {c_wheel_of_fortune} [Le Casino] Une nouvelle carte avec huit lieux : la Taverne, le Marché, le Tailleur, la Forge, la Bibliothèque, le Terrain d'entraînement, l'Arcade et le Champ de courses.
+ {j_golden} [Progression] De l'XP et 100 niveaux répartis en 7 rangs, des quêtes quotidiennes et hebdomadaires, des Parcours et plus de 200 succès. Les niveaux et les quêtes rapportent des Balacoins à dépenser au Marché.
+ {j_hologram} [Hologramme] La mascotte de l'Overhaul. Hologramme vous fait la visite au premier lancement et explique chaque nouvel écran la première fois que vous l'ouvrez. La visite peut être passée ou rejouée. Hologram se tient aussi à côté de l'As sur l'écran titre, et deux Hologram vous accueillent dans le menu multijoueur.
+ [Modes 1v1] Rivaux : les boss blinds sont en PvP dès la mise 2. FaceOff : chaque blind est en PvP. Ascension : pas de PvP, le plus loin gagne. Course : le premier à finir la mise visée gagne. Chassé-croisé : après chaque boss blind, vous échangez votre partie avec l'adversaire (jeu, jokers, argent, tout sauf les vies), après un écran Prêt et un compte à rebours de 3 secondes.
+ [Modes de groupe] Battle Royale : les plus petits scores de chaque blind PvP perdent une vie, le dernier en vie gagne. Équipes : des équipes de 2 à 4 additionnent leurs scores et partagent leurs vies. Raid coop : tout le monde marque contre un boss commun, avec des vies partagées et un bonus pour le meilleur score. La Course se joue aussi à plusieurs.
+ [Blinds PvP] Les deux joueurs jouent la même blind, le plus gros score gagne. Le perdant perd une vie, et sans vie la partie est perdue. Les groupes ont leurs propres blinds : Blind royale, Choc des équipes et Boss de raid.
+ [Classé] Des Rivaux avec des règles fixes et une sélection de jeux où chacun bannit 2 jeux sur 5. 10 rangs, de Pierre à TRUE JIMBO, avec 3 paliers chacun. Une saison tous les trois mois, avec une remise à zéro partielle, et un badge et une pochette de saison pour votre meilleur rang. L'XP classée ouvre des paquets de titres, pochettes, cadres de cartes et de jokers, flammes, explosions et célébrations.
+ [Quotidien et Hebdo] Un défi multijoueur avec des règles, un jeu et une seed choisis par le serveur, un ou deux modificateurs au hasard, et un classement.
+ [Réglages du salon] L'hôte choisit les vies, la mise où commence le PvP, la mise finale, le jeu (ou laisse chacun choisir), la mise, la seed, les minuteurs, les délais gratuits, le vol de vie, un bonus de victoire PvP, l'argent de rattrapage, le score adverse caché, une file de boutique commune, les cartes bannies et toutes les règles de partie perso. 3 emplacements pour garder ses réglages.
+ [Règles prêtes] Des règles toutes faites pour chaque mode : Classique, Équilibré, Vanilla, Combustion lente, Tournoi, Pénurie, Sprint, Chaos, Duel express, Tir rapide, Marathon, Canon de verre, Mort subite, Bain de sang, Sans porteur et Héroïque.
+ [Modificateurs] Des couches que l'hôte peut cumuler : trois vitesses d'horloge, cartes de verre solides ou fragiles, Inflation, Sans intérêts, Taxe de défausse, Économe, Spartiate, boutique plus grande ou plus petite, Prix mystère, Poches partagées, Score instable, Sans sceaux rouges, Sans jeux de hasard, Pénurie, Cartes face cachée et Jokers éternels.
+ [Pièges] Les Paquets piège de la boutique permettent de poser un des 12 pièges cachés sur l'adversaire. Par exemple, Péage vous fait toucher une part de ses relances, et Piège à ours rend Location le prochain joker qu'il achète. Jusqu'à 3 pièges peuvent attendre un même joueur.
+ [Jokers multijoueur] 20 jokers qui n'existent qu'en multijoueur, comme Trêve, Rancune, Match miroir et Flambeur, et des jokers faits pour l'Ascension, la Course, le Battle Royale, les Équipes et le Raid. Ils portent une teinte violette et une petite marque MP dans le coin.
+ [Jeux et mises] Les jeux Lilas, Voyant, Mandarine, Cobalt, Gémeaux et Aléatoire. Le jeu Aléatoire donne des jetons et un multi au hasard à chaque main et mélange les prix, les valeurs des cartes et les paquets, avec un curseur de chaos. Trois mises multijoueur : Nova, Éclipse et Éclipse+.
+ [Refontes] Certaines règles modifient quelques cartes de base : Bulletin raté, Héliotrope, cartes de verre, Ticket doré, Eau gazeuse, Haricot tortue et Ouija. Le salon et Collection > Refontes indiquent lesquelles.
+ [Amis et chat] Liste d'amis avec statut en ligne, invitations et Demander à rejoindre, messages privés, chat du salon qui marche pendant la partie, 12 emotes, mettre en sourdine, signaler et bloquer. Le chat demande votre âge une fois et est réservé aux 13 ans et plus. Les cosmétiques en double peuvent être offerts à des amis.
+ [Replays et spectateur] Les parties finies sont gardées en replays, avec pause, vitesse et saut. Regardez en direct les parties publiques ou celles de vos amis, ou regardez les autres quand vous avez joué vos mains.
+ [Bots et salons moddés] L'hôte peut ajouter des bots Facile, Moyen ou Difficile. Les salons peuvent utiliser des mods (bêta) : ils affichent leurs mods et ceux qui manquent s'installent quand vous rejoignez.
+ [4 nouvelles mises] Après la mise or. Chaos : les paquets offrent un choix de moins. Apocalypse : les boss blinds affaiblissent aussi une couleur au hasard. Oubli : un joker au hasard est affaibli à chaque blind. Transcendance : chaque boss blind est une blind finale. Chacune garde les mises d'avant, recule d'une mise la victoire (de 10 à 13) et a son propre autocollant.
+ [Parties perso] Vos propres règles en 8 catégories : bases, économie, blinds, boutique, jeu, objets, bannis et fun. Mains, défausses, taille de main, emplacements, argent, intérêts, taille des blinds, chances en boutique, taille du jeu de 1 à 208 cartes, jokers et bons de départ, cartes bannies, un randomiseur de nombres et plus encore. Vos règles se gardent en préréglages.
+ [Parties aléatoires] Un jeu et une mise au hasard, ou une Partie perso aléatoire avec des règles tirées au sort que vous pouvez lire avant de commencer.
+ [Partie du jour] La même seed pour tout le monde chaque jour, avec 2 contraintes, 1 bonus et un joker de départ. Un essai compté par jour, une série, et un classement avec un onglet Amis.
+ [Speedruns] Catégories Mise 2, Mise 4 et Any%, sur une seed de la semaine ou au hasard. Un chrono avec temps par mise, records perso, un classement en ligne et les replays des meilleures parties.
+ [Nouveaux défis] 10 nouveaux défis : Faillite, L'Épreuve, Petites mains, Gros cogneur, Canon de verre, Le Collectionneur, Joker, Course contre la montre, L'Alchimiste et Dualité.
+ [Entraînement aux boss] Affrontez n'importe quel boss déjà rencontré, avec le jeu et l'équipement de votre choix, même repris d'une ancienne partie. Pas de récompense, rien ne compte dans vos stats.
+ [Historique] Vos 200 dernières parties avec leur seed, jeu, mise, meilleure main et jokers finaux. Rejouez la seed, ou regardez le replay d'une de vos 50 dernières parties.
+ [Bibliothèque de seeds] Gardez des seeds avec leur jeu et leur mise, ou collez-en une, et jouez-les plus tard.
+ [Créateur de jeux] Créez vos propres jeux : règles, argent, chances en boutique, les cartes exactes du jeu, objets de départ et contraintes. Partagez-les avec un code texte.
+ [Triches] Activez-les avant une partie, puis utilisez le bouton Triches (déplaçable) pour ajouter jokers, cartes, consommables et bons, monter les mains, changer l'argent, les mains et les emplacements, ou gagner la blind. Une partie avec triches ne fait pas progresser.
+ [Stats] Stats solo et multijoueur : victoires, séries, meilleure main, mise la plus haute, temps de jeu, résultats par jeu et par mise, et vos jokers et mains préférés.
+ [Marché] Dépensez vos Balacoins en paquets de cosmétiques : paquets Palette, Bouffon, Pochette, Éclat et Titre, paquets Jumbo, et les Caisses de la Taverne et Légendaires. Toutes les chances sont dans l'onglet Chances, les objets que vous n'avez pas sont 3 fois plus probables, les doublons redeviennent des Balacoins, et les Caisses légendaires donnent un Légendaire au moins toutes les 40 cartes.
+ [Tailleur] Équipez vos cosmétiques : icône de profil et son éclat, titre, palettes de couleurs, tapis de table, dos de cartes en 5 finitions, flammes de score, célébrations, portraits et tenues de Jimbo. La palette Polychrome a son propre éditeur : choisissez chaque couleur par teinte, saturation et luminosité et voyez le résultat en direct. Nouvelle palette légendaire au Marché : Chewing-gum.
+ [Arcade] 10 mini-jeux : Plus ou moins, Mémoire des jokers, Nomme la main, Trouve l'as, Blackjack, Tape-Joker, Machine à sous, Bats la blind, Jimbo Run et Jimbo Jam, un jeu de rythme qui peut jouer n'importe quelle chanson de votre Jukebox. Chacun garde votre meilleur score, et vous pouvez y jouer en attendant en multijoueur.
+ [Dans la Forge] Les règles des jokers se construisent avec 20 déclencheurs, 23 conditions et 26 effets, avec des variables. L'éditeur de pixels a des outils de dessin, de formes et de sélection, un calque d'âme et l'import d'images. Exportez vos créations en fichier .forgemod, publiez-les en ligne ou faites-les jouer à tout votre salon.
+ [Quêtes et succès] 4 quêtes du jour (un échange gratuit par jour), 4 quêtes de la semaine, et 24 Parcours de 3 à 5 étapes. Les succès ont des popups, des raretés, et donnent des titres, des badges et des cosmétiques.
+ [Normal et Moddé] Deux jeux séparés, à changer depuis l'écran titre. Normal ne charge jamais de mods, Moddé charge les vôtres. Chacun a ses 3 profils, donc les mods ne touchent pas vos sauvegardes principales.
+ [Mods] La plupart des mods Steamodded et Lovely marchent, sur Android aussi. Le menu Mods les active, les désactive, ouvre leurs réglages, les met à jour et les supprime. Un .zip de mod dans Téléchargements s'installe au démarrage. Si un mod fait planter le jeu au démarrage, le lancement suivant le désactive et vous dit lequel.
+ [Workshop] Parcourez, cherchez et installez des mods du Balatro Mod Index sans quitter le jeu. Les mods requis s'installent tout seuls, et chaque mod indique s'il marche sur votre plateforme.
+ {j_hologram} [Bot-latro] Regardez jouer notre bot entraîné. Loyal (w15) voit seulement ce que vous voyez et gagne environ 6 % des parties en mise Or, avec une victoire sur chaque deck. Le Voyant lit la graine. L'onglet Stats montre ses résultats par deck et par mise.
+ [Lanceur] Pour Windows, macOS, Linux et Android. Il trouve votre Balatro (Steam, l'app Xbox, Flatpak), construit l'Overhaul à partir de lui, reprend votre progression Balatro ou repart de zéro, sauvegarde vos parties et ajoute des raccourcis. Sur PC, il peut aussi créer une app Android depuis votre copie Steam. Sur Android, il crée une deuxième app, Balatro Overhaul, qui s'ouvre directement sur le jeu, se met à jour toute seule et reprend vos sauvegardes.
+ [Mises à jour et sauvegardes] Le jeu et le lanceur vous préviennent d'une mise à jour et l'installent, vos sauvegardes restent. Exportez tous vos profils en un seul .zip et importez-les sur un autre appareil. Une copie est faite avant chaque import.
+ [Contrôles] Support complet de la manette avec réassignation et sélection glissée, une partie entière jouable au clavier avec réassignation, le tactile sur PC et téléphone, un mode pavé tactile et un réglage de vitesse du curseur.
+ [Aides] Aperçu du score, infos sous chaque joker, Jimbo qui commente votre partie, sélection en glissant, valeur de vente totale, redémarrage rapide, garde-intérêts, vente sécurisée, ouverture rapide des paquets, touche de vitesse jusqu'à 20x en solo, touches muet, pause quand vous changez de fenêtre et recherche dans les réglages.
+ [Jukebox] Jouez votre propre musique à la place de la bande-son. Mettez des fichiers mp3, ogg, wav ou flac dans le dossier Ma musique, ou laissez le jeu les trouver dans Téléchargements.
+ [Affichage et performances] Un mode performance, et des options séparées pour la netteté, le fond, l'éclat des cartes, les particules et les images par seconde. Filtres de couleur, compteur d'IPS, taille de l'interface, et Remplir l'écran sur téléphone en portrait.
+ [Langues] Tout l'Overhaul est en anglais, en français et en espagnol.
- Mise bleue : au lieu de -1 défausse, les articles de la boutique coûtent 1 $ de plus et les relances augmentent de 2 $. Les mises au-dessus la gardent, sauf Nova et Éclipse.
- Les cartes joker ne peuvent pas être affaiblies par les boss blinds.
- Matador donne 2 $ par défausse utilisée pendant une boss blind.
- La Mort et les autres cartes aux valeurs augmentées marchent au-delà de leur valeur normale.
- Une blind déjà battue ne peut pas être rejouée.
- L'écran titre a une fenêtre Nouveautés, et À propos contient le journal des changements, les crédits et un lien Ko-fi.
- Les rapports de plantage sont activés par défaut. Ils envoient l'erreur, la version, votre plateforme et votre liste de mods. Désactivez-les dans Réglages > Compte.

### es Overhaul 2.0 (versión preliminar)
+ {j_ring_master} [Multijugador] Juega en línea 1 contra 1 o en grupos de hasta 8, contra amigos, desconocidos o bots, en casual o clasificatoria. Partida rápida, salas públicas o privadas con un código de 4 letras, lista de salas, y tu sitio se guarda 15 minutos si te desconectas.
+ {c_chariot} [La Forja] Crea tus propios comodines, tarots, planetas, espectrales, vales, mejoras, sellos, ediciones, etiquetas, ciegas, apuestas, barajas y sobres. Dibújalos en el editor de píxeles, úsalos en tus partidas y compártelos en línea.
+ {c_wheel_of_fortune} [El Casino] Un nuevo mapa con ocho lugares: la Taberna, el Mercado, el Sastre, la Forja, la Biblioteca, el Campo de entrenamiento, el Arcade y el Hipódromo.
+ {j_golden} [Progresión] XP y 100 niveles en 7 rangos, misiones diarias y semanales, Trayectos y más de 200 logros. Los niveles y las misiones dan Balacoins para gastar en el Mercado.
+ {j_hologram} [Holograma] La mascota del Overhaul. Holograma te enseña todo en el primer inicio y explica cada pantalla nueva la primera vez que la abres. Puedes saltarte el recorrido o repetirlo. Hologram también está junto al As en la pantalla de título, y dos Hologram te reciben en el menú multijugador.
+ [Modos 1 contra 1] Rivales: las ciegas jefe son PvP desde la apuesta 2. FaceOff: todas las ciegas son PvP. Ascensión: sin PvP, gana quien llegue más lejos. Carrera: gana el primero en superar la apuesta objetivo. Intercambio: después de cada ciega jefe cambias tu partida con la del rival (baraja, comodines, dinero, todo menos las vidas), tras una pantalla de listo y una cuenta atrás de 3 segundos.
+ [Modos de grupo] Battle Royale: las puntuaciones más bajas de cada ciega PvP pierden una vida, gana el último en pie. Equipos: equipos de 2 a 4 suman sus puntuaciones y comparten las vidas. Raid cooperativo: todos puntúan contra un jefe común, con vidas compartidas y un premio para la mejor puntuación. La Carrera también se juega con más jugadores.
+ [Ciegas PvP] Los dos jugadores juegan la misma ciega y gana la puntuación más alta. El que pierde pierde una vida, y sin vidas pierde la partida. Los grupos tienen sus propias ciegas: Ciega real, Choque de equipos y Jefe de raid.
+ [Clasificatoria] Rivales con reglas fijas y una selección de barajas donde cada jugador veta 2 de 5. 10 rangos, de Piedra a TRUE JIMBO, con 3 niveles cada uno. Una temporada cada tres meses, con un reinicio parcial, y una insignia y una funda de temporada para tu mejor rango. La XP de clasificatoria abre sobres de títulos, fundas, marcos de cartas y comodines, llamas, explosiones y celebraciones.
+ [Diario y Semanal] Un desafío multijugador con reglas, baraja y semilla elegidas por el servidor, uno o dos modificadores al azar, y una clasificación.
+ [Ajustes de sala] El anfitrión elige las vidas, la apuesta en la que empieza el PvP, la apuesta final, la baraja (o deja que cada uno elija), la apuesta, la semilla, los temporizadores, los tiempos muertos gratis, el robo de vida, un premio por ganar el PvP, dinero de remontada, la puntuación rival oculta, una cola de tienda compartida, las cartas prohibidas y cualquier regla de partida personalizada. 3 huecos para guardar ajustes.
+ [Reglas listas] Reglas ya hechas para cada modo: Clásico, Equilibrado, Vanilla, Fuego lento, Torneo, Escasez, Sprint, Caos, Duelo rápido, Fuego rápido, Maratón, Cañón de cristal, Muerte súbita, Baño de sangre, Sin cargar y Heroico.
+ [Modificadores] Capas que el anfitrión puede sumar: tres velocidades de reloj, cartas de cristal resistentes o frágiles, Inflación, Sin intereses, Impuesto de descarte, Ahorrador, Espartano, tienda más grande o más pequeña, Precios misteriosos, Bolsillos compartidos, Puntuación inestable, Sin sellos rojos, Sin apuestas, Escasez, Cartas boca abajo y Comodines eternos.
+ [Trampas] Los Sobres trampa de la tienda te dejan poner una de 12 trampas ocultas al rival. Por ejemplo, Peaje hace que sus cambios de tienda te paguen, y Cepo convierte en Alquiler el próximo comodín que compre. Hasta 3 trampas pueden esperar a un mismo jugador.
+ [Comodines multijugador] 20 comodines que solo existen en multijugador, como Tregua, Rencor, Duelo espejo y Gran apostador, y comodines hechos para Ascensión, Carrera, Battle Royale, Equipos y Raid. Llevan un tinte morado y una pequeña marca MP en la esquina.
+ [Barajas y apuestas] Las barajas Lila, Vidente, Mandarina, Cobalto, Géminis y Aleatoria. La baraja Aleatoria da fichas y multi al azar a cada mano y mezcla precios, valores de cartas y sobres, con un control de caos. Tres apuestas multijugador: Nova, Eclipse y Eclipse+.
+ [Rediseños] Algunas reglas cambian unas cuantas cartas base: Voto colgante, Heliotropo, cartas de cristal, Boleto dorado, Soda, Judía tortuga y Ouija. La sala y Colección > Rediseños muestran cuáles.
+ [Amigos y chat] Lista de amigos con estado en línea, invitaciones y Pedir unirse, mensajes privados, chat de sala que sigue funcionando en la partida, 12 emotes, silenciar, denunciar y bloquear. El chat pregunta tu edad una vez y es para mayores de 13 años. Los cosméticos repetidos se pueden regalar a amigos.
+ [Repeticiones y espectador] Las partidas terminadas se guardan como repeticiones con pausa, velocidad y salto. Mira en directo partidas públicas o de tus amigos, o mira a los demás cuando hayas jugado tus manos.
+ [Bots y salas con mods] El anfitrión puede añadir bots Fácil, Medio o Difícil. Las salas pueden usar mods (beta): muestran sus mods y los que faltan se instalan al unirte.
+ [4 apuestas nuevas] Después de la apuesta dorada. Caos: los sobres ofrecen una opción menos. Apocalipsis: las ciegas jefe también debilitan un palo al azar. Olvido: un comodín al azar queda debilitado en cada ciega. Trascendencia: todas las ciegas jefe son finales. Cada una mantiene las anteriores, sube en uno la apuesta para ganar (de 10 a 13) y tiene su propia pegatina.
+ [Partidas personalizadas] Tus propias reglas en 8 categorías: básicas, economía, ciegas, tienda, baraja, objetos, prohibidos y diversión. Manos, descartes, tamaño de mano, huecos, dinero, intereses, tamaño de las ciegas, probabilidades de la tienda, baraja de 1 a 208 cartas, comodines y vales iniciales, cartas prohibidas, un aleatorizador de números y más. Guarda tus reglas como preajustes.
+ [Partidas aleatorias] Una baraja y una apuesta al azar, o una Partida personalizada aleatoria con reglas al azar que puedes leer antes de empezar.
+ [Partida diaria] La misma semilla para todos cada día, con 2 giros, 1 ventaja y un comodín inicial. Un intento puntuado al día, una racha y una clasificación con pestaña de Amigos.
+ [Speedruns] Categorías Apuesta 2, Apuesta 4 y Any%, con una semilla semanal o al azar. Un cronómetro con parciales por apuesta, récords personales, una clasificación en línea y repeticiones de las mejores partidas.
+ [Desafíos nuevos] 10 desafíos nuevos: Bancarrota, El Guantelete, Manos pequeñas, Pegador, Cañón de cristal, El Coleccionista, Comodín, Contrarreloj, El Alquimista y Dualidad.
+ [Práctica de jefes] Enfréntate a cualquier jefe que ya hayas visto, con la baraja y el equipo que quieras, incluso sacado de una partida anterior. Sin premios, y nada cuenta en tus estadísticas.
+ [Historial] Tus últimas 200 partidas con su semilla, baraja, apuesta, mejor mano y comodines finales. Vuelve a jugar la semilla o mira la repetición de cualquiera de tus últimas 50 partidas.
+ [Biblioteca de códigos] Guarda semillas con su baraja y apuesta, o pega una, y juégalas más tarde.
+ [Creador de barajas] Crea tus propias barajas: reglas, dinero, probabilidades de la tienda, las cartas exactas de la baraja, objetos iniciales y giros. Compártelas con un código de texto.
+ [Trucos] Actívalos antes de una partida y usa el botón Trucos (se puede mover) para añadir comodines, cartas, consumibles y vales, subir manos, cambiar dinero, manos y huecos, o ganar la ciega. Una partida con trucos no da progreso.
+ [Estadísticas] Estadísticas en solitario y multijugador: victorias, rachas, mejor mano, apuesta más alta, tiempo jugado, resultados por baraja y apuesta, y tus comodines y manos favoritos.
+ [Mercado] Gasta Balacoins en sobres de cosméticos: sobres Paleta, Bufón, Funda, Brillo y Título, sobres Jumbo, y las Cajas de la Taberna y Legendarias. Todas las probabilidades están en la pestaña Probabilidades, lo que no tienes sale 3 veces más, los repetidos vuelven a ser Balacoins, y las Cajas legendarias dan un Legendario al menos cada 40 cartas.
+ [Sastre] Equipa tus cosméticos: icono de perfil y su brillo, título, paletas de colores, tapete, dorsos de carta en 5 acabados, llamas de puntuación, celebraciones, retratos y aspectos de Jimbo. La paleta Policromática tiene su propio editor: elige cada color por tono, saturación y brillo y míralo en directo. Nueva paleta legendaria en el Mercado: Chicle.
+ [Arcade] 10 minijuegos: Mayor o menor, Memoria de comodines, Nombra la mano, Encuentra el as, Blackjack, Golpea al comodín, Tragaperras, Vence a la ciega, Jimbo Run y Jimbo Jam, un juego de ritmo que puede tocar cualquier canción de tu Jukebox. Cada uno guarda tu mejor puntuación, y puedes jugarlos mientras esperas en multijugador.
+ [Dentro de la Forja] Las reglas de los comodines se crean con 20 activadores, 23 condiciones y 26 efectos, con variables. El editor de píxeles tiene herramientas de dibujo, formas y selección, una capa de alma e importación de imágenes. Exporta tus creaciones como archivo .forgemod, publícalas en línea o haz que toda tu sala juegue con ellas.
+ [Misiones y logros] 4 misiones diarias (un cambio gratis al día), 4 semanales, y 24 Trayectos de 3 a 5 etapas. Los logros tienen avisos, rarezas, y dan títulos, insignias y cosméticos.
+ [Normal y Con mods] Dos juegos separados, que se cambian desde la pantalla de título. Normal nunca carga mods, Con mods carga los tuyos. Cada uno tiene sus 3 perfiles, así que los mods no tocan tus partidas principales.
+ [Mods] La mayoría de los mods de Steamodded y Lovely funcionan, también en Android. El menú Mods los activa, desactiva, abre sus ajustes, los actualiza y los quita. Un .zip de mod en Descargas se instala al iniciar. Si un mod cuelga el juego al iniciar, el siguiente inicio lo desactiva y te dice cuál fue.
+ [Workshop] Explora, busca e instala mods del Balatro Mod Index sin salir del juego. Los mods necesarios se instalan solos, y cada mod indica si funciona en tu plataforma.
+ {j_hologram} [Bot-latro] Mira jugar a nuestro bot entrenado. Limpio (w15) ve solo lo que tú ves y gana cerca del 6 % de las partidas en apuesta Oro, con una victoria en cada baraja. El Vidente lee la semilla. La pestaña Stats muestra sus resultados por baraja y apuesta.
+ [Lanzador] Para Windows, macOS, Linux y Android. Encuentra tu Balatro (Steam, la app de Xbox, Flatpak), crea el Overhaul a partir de él, trae tu progreso de Balatro o empieza de cero, hace copias de tus partidas y añade accesos directos. En PC también puede crear una app de Android desde tu copia de Steam. En Android crea una segunda app, Balatro Overhaul, que se abre directamente en el juego, se actualiza sola y se lleva tus partidas.
+ [Actualizaciones y partidas] El juego y el lanzador te avisan de una actualización y la instalan, y tus partidas se quedan. Exporta todos tus perfiles en un solo .zip e impórtalos en otro dispositivo. Se hace una copia antes de cada importación.
+ [Controles] Soporte completo de mando con reasignación y selección deslizando, una partida entera jugable con teclado y reasignación, táctil en PC y móvil, un modo panel táctil y un ajuste de velocidad del cursor.
+ [Ayudas] Vista previa de la puntuación, información bajo cada comodín, Jimbo comentando tu partida, seleccionar arrastrando, valor de venta total, reinicio rápido, protección de intereses, venta segura, sobres rápidos, una tecla de velocidad hasta 20x en solitario, teclas de silencio, pausa al cambiar de ventana y búsqueda en los ajustes.
+ [Jukebox] Pon tu propia música en lugar de la banda sonora. Mete archivos mp3, ogg, wav o flac en la carpeta Mi música, o deja que el juego los busque en Descargas.
+ [Pantalla y rendimiento] Un modo rendimiento, y opciones separadas para nitidez, fondo, brillo de cartas, partículas y fotogramas por segundo. Filtros de color, contador de FPS, tamaño de la interfaz y Llenar la pantalla en el móvil en vertical.
+ [Idiomas] Todo el Overhaul está en inglés, francés y español.
- Apuesta azul: en lugar de -1 descarte, los artículos de la tienda cuestan 1 $ más y los cambios suben 2 $. Las apuestas superiores la mantienen, salvo Nova y Eclipse.
- Las cartas comodín no pueden ser debilitadas por las ciegas jefe.
- Matador da 2 $ por cada descarte usado durante una ciega jefe.
- La Muerte y las demás cartas con valores aumentados funcionan por encima de su valor normal.
- Una ciega ya superada no se puede volver a jugar.
- La pantalla de título tiene una ventana de Novedades, y Acerca de tiene el registro de cambios, los créditos y un enlace a Ko-fi.
- Los informes de errores están activados por defecto. Envían el error, la versión, tu plataforma y tu lista de mods. Desactívalos en Ajustes > Cuenta.

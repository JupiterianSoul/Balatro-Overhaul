local T = {}

T.TOUR = {
    ovt_welcome = {
        en = {"Hi! I'm {C:attention}Hologram{}, the", "mascot of {C:attention}Balatro Overhaul{}.", "Let me show you what's new.", "It only takes a minute!"},
        fr = {"Salut ! Moi, c'est {C:attention}Hologramme{},", "la mascotte de {C:attention}Balatro Overhaul{}.", "Je te montre les nouveautés,", "ça ne prend qu'une minute !"},
        es = {"¡Hola! Soy {C:attention}Holograma{}, la", "mascota de {C:attention}Balatro Overhaul{}.", "Te enseño todo lo nuevo,", "¡solo es un minuto!"},
    },
    ovt_play = {
        en = {"{C:blue}Play{} starts a solo run:", "a {C:attention}Seeded run{}, a {C:attention}Challenge{}", "or a {C:attention}Custom run{} where you", "pick the rules yourself."},
        fr = {"{C:blue}Jouer{} lance une partie solo :", "une {C:attention}partie avec seed{}, un {C:attention}Défi{}", "ou une {C:attention}partie perso{} dont", "tu choisis toi-même les règles."},
        es = {"{C:blue}Jugar{} empieza una partida", "{C:attention}con códigos{}, un {C:attention}Desafío{} o", "una {C:attention}partida personalizada{}", "con las reglas que tú elijas."},
    },
    ovt_cheats = {
        en = {"{C:red}Cheats{}: allow them with the", "toggle next to {C:attention}Seeded run{},", "then use the {C:red}Cheats{} button", "in a run. You can drag it."},
        fr = {"{C:red}Triches{} : active l'interrupteur", "près de {C:attention}Partie avec seed{},", "puis le bouton {C:red}Triches{} en", "partie. Tu peux le déplacer."},
        es = {"{C:red}Trucos{}: actívalos junto a", "{C:attention}Partida con códigos{} y usa", "el botón {C:red}Trucos{} en partida.", "Puedes moverlo."},
    },
    ovt_multiplayer = {
        en = {"{C:blue}Multiplayer{}: play online in", "{C:attention}Rivals{}, {C:attention}FaceOff{}, {C:attention}Battle Royale{},", "{C:attention}Co-op Raid{}, {C:attention}Switcheroo{} and more,", "or climb the {C:attention}Ranked{} ladder."},
        fr = {"{C:blue}Multijoueur{} : joue en ligne en", "{C:attention}Rivaux{}, {C:attention}FaceOff{}, {C:attention}Battle Royale{},", "{C:attention}Raid coop{}, {C:attention}Chassé-croisé{} et plus,", "ou grimpe en {C:attention}Classé{}."},
        es = {"{C:blue}Multijugador{}: juega en línea a", "{C:attention}Rivales{}, {C:attention}FaceOff{}, {C:attention}Battle Royale{},", "{C:attention}Raid cooperativo{}, {C:attention}Intercambio{}", "y más, o sube en {C:attention}Clasificatoria{}."},
    },
    ovt_lobbies = {
        en = {"Make a {C:attention}room{} or join one with", "a code. The host sets the deck,", "the stake and the {C:attention}rules{}.", "Friends and chat are there too."},
        fr = {"Crée un {C:attention}salon{} ou rejoins-en un", "avec un code. L'hôte choisit le", "jeu, la mise et les {C:attention}règles{}.", "Amis et chat sont là aussi."},
        es = {"Crea una {C:attention}sala{} o entra en una", "con un código. El anfitrión elige", "baraja, apuesta y {C:attention}reglas{}.", "Amigos y chat también están ahí."},
    },
    ovt_casino = {
        en = {"In {C:green}The Casino{},", "the {C:attention}Tailor{} dresses your deck,", "the {C:money}Market{} sells cosmetics and", "{C:attention}The Forge{} makes your own cards."},
        fr = {"Au {C:green}Casino{},", "le {C:attention}Tailleur{} habille ton jeu,", "le {C:money}Marché{} vend des cosmétiques", "et {C:attention}la Forge{} crée tes cartes."},
        es = {"En {C:green}El Casino{},", "el {C:attention}Sastre{} viste tu baraja,", "el {C:money}Mercado{} vende cosméticos y", "{C:attention}la Forja{} crea tus propias cartas."},
    },
    ovt_casino_more = {
        en = {"There's more: the {C:attention}Seed Library{},", "{C:attention}Boss Practice{}, the {C:attention}Arcade{},", "your {C:attention}Run History{} and the", "{C:attention}Racetrack{} for speedruns."},
        fr = {"Et aussi : la {C:attention}Bibliothèque{},", "l'{C:attention}Entraînement boss{}, l'{C:attention}Arcade{},", "ton {C:attention}Historique{} de parties", "et le {C:attention}Circuit{} des speedruns."},
        es = {"Y también: la {C:attention}Biblioteca{},", "la {C:attention}Práctica de jefes{}, el {C:attention}Salón{},", "tu {C:attention}Historial{} de partidas y", "el {C:attention}Circuito{} de speedruns."},
    },
    ovt_progression = {
        en = {"{C:green}Progression{}: every run gives {C:attention}XP{}.", "Level up for rewards, and finish", "{C:attention}Quests{} for {C:money}Balacoins{}. Done", "quests wait there for you."},
        fr = {"{C:green}Progression{} : chaque partie donne", "de l'{C:attention}XP{}. Monte de niveau, finis", "des {C:attention}Quêtes{} pour des {C:money}Balacoins{}.", "Elles t'attendent là une fois finies."},
        es = {"{C:green}Progreso{}: cada partida da {C:attention}XP{}.", "Sube de nivel y completa", "{C:attention}Misiones{} para ganar {C:money}Balacoins{}.", "Las terminadas te esperan ahí."},
    },
    ovt_achievements = {
        en = {"{C:attention}Achievements{}: lots of new ones,", "solo and multiplayer. A popup", "shows up the moment you", "unlock one."},
        fr = {"{C:attention}Succès{} : plein de nouveaux,", "en solo et en multijoueur.", "Une fenêtre s'affiche dès", "que tu en débloques un."},
        es = {"{C:attention}Logros{}: muchos nuevos,", "en solitario y multijugador.", "Aparece un aviso en cuanto", "desbloqueas uno."},
    },
    ovt_collection = {
        en = {"The {C:attention}Collection{} has every card,", "plus a {C:blue}Multiplayer{} part with", "the MP jokers, decks, stakes", "and blinds."},
        fr = {"La {C:attention}Collection{} montre chaque carte,", "plus une partie {C:blue}Multijoueur{}", "avec les jokers, jeux, mises", "et blindes du MP."},
        es = {"La {C:attention}Colección{} tiene cada carta,", "y una parte {C:blue}Multijugador{} con", "los comodines, barajas, apuestas", "y ciegas del MP."},
    },
    ovt_replays = {
        en = {"{C:attention}Replays{}: watch a finished match", "from {C:attention}Profile{} > {C:attention}History{} in", "Multiplayer, or a solo run", "from your {C:attention}Run History{}."},
        fr = {"{C:attention}Replays{} : revois un match fini", "dans {C:attention}Profil{} > {C:attention}Historique{} en", "multijoueur, ou une partie solo", "depuis ton {C:attention}Historique{}."},
        es = {"{C:attention}Repeticiones{}: mira una partida", "desde {C:attention}Perfil{} > {C:attention}Historial{} en", "multijugador, o una partida solo", "desde tu {C:attention}Historial{}."},
    },
    ovt_speedrun = {
        en = {"{C:attention}Speedruns{}: start a timed run", "at the {C:attention}Racetrack{} and beat your", "best time. Turn the timer on", "for any run in {C:attention}Options{}."},
        fr = {"{C:attention}Speedruns{} : lance une partie", "chronométrée au {C:attention}Circuit{} et bats", "ton record. Active le chrono pour", "toutes tes parties dans {C:attention}Options{}."},
        es = {"{C:attention}Speedruns{}: empieza una partida", "cronometrada en el {C:attention}Circuito{} y", "bate tu récord. Activa el crono", "para cualquier partida en {C:attention}Opciones{}."},
    },
    ovt_options = {
        en = {"{C:attention}Options{}: {C:attention}Stats{} for your solo", "and MP numbers, {C:attention}Settings{} with", "a search, and {C:attention}Performance{}", "to make the game lighter."},
        fr = {"{C:attention}Options{} : tes {C:attention}Statistiques{}", "solo et multi, les {C:attention}Paramètres{}", "avec une recherche et la partie", "{C:attention}Performance{} pour alléger le jeu."},
        es = {"{C:attention}Opciones{}: tus {C:attention}Estadísticas{}", "solo y multijugador, la", "{C:attention}Configuración{} con buscador y", "{C:attention}Rendimiento{} para aligerar el juego."},
    },
    ovt_updates = {
        en = {"After an update, {C:attention}What's new{}", "sums it up. When a new version", "is out, an {C:green}Update{} button", "shows up on the main menu."},
        fr = {"Après une mise à jour, {C:attention}Nouveautés{}", "la résume. Quand une version sort,", "un bouton {C:green}Mettre à jour{}", "apparaît au menu principal."},
        es = {"Tras una actualización, {C:attention}Novedades{}", "la resume. Cuando sale una versión,", "aparece un botón {C:green}Actualizar{}", "en el menú principal."},
    },
    ovt_farewell = {
        en = {"That's the tour! {C:attention}Settings{} >", "{C:attention}Guide{} explains each feature", "and replays this tutorial.", "Now go break some blinds!"},
        fr = {"Fin de la visite ! {C:attention}Paramètres{} >", "{C:attention}Guide{} explique chaque fonction", "et relance ce tutoriel.", "À toi de casser des blindes !"},
        es = {"¡Fin del recorrido! {C:attention}Configuración{} >", "{C:attention}Guía{} explica cada función", "y repite este tutorial.", "¡A romper ciegas!"},
    },
    ovt_tip_casino = {
        en = {"Welcome to {C:green}The Casino{}!", "Each place opens a part of", "the Overhaul: walk around", "and try them all."},
        fr = {"Bienvenue au {C:green}Casino{} !", "Chaque lieu ouvre une partie", "de l'Overhaul : fais un tour", "et essaie-les tous."},
        es = {"¡Bienvenido a {C:green}El Casino{}!", "Cada lugar abre una parte", "de Overhaul: date una vuelta", "y pruébalos todos."},
    },
    ovt_tip_quests = {
        en = {"{C:attention}Quests{}: daily, weekly and", "repeatable goals. Finish one,", "then redeem it for {C:money}Balacoins{}", "and {C:attention}XP{}."},
        fr = {"{C:attention}Quêtes{} : objectifs du jour,", "de la semaine ou à refaire.", "Finis-en une, puis récupère", "tes {C:money}Balacoins{} et ton {C:attention}XP{}."},
        es = {"{C:attention}Misiones{}: diarias, semanales", "y repetibles. Termina una y", "canjéala por {C:money}Balacoins{}", "y {C:attention}XP{}."},
    },
    ovt_tip_tailor = {
        en = {"The {C:attention}Tailor{} dresses your game:", "card backs, sleeves, colours,", "your profile icon and badges.", "Pick a tab to start."},
        fr = {"Le {C:attention}Tailleur{} habille ton jeu :", "dos de cartes, pochettes, couleurs,", "icône de profil et badges.", "Choisis un onglet pour commencer."},
        es = {"El {C:attention}Sastre{} viste tu juego:", "dorsos, fundas, colores,", "tu icono de perfil e insignias.", "Elige una pestaña para empezar."},
    },
    ovt_tip_market = {
        en = {"The {C:money}Market{} sells cosmetics", "for {C:money}Balacoins{}. Earn them by", "playing runs and finishing", "{C:attention}Quests{}."},
        fr = {"Le {C:money}Marché{} vend des cosmétiques", "contre des {C:money}Balacoins{}. Gagne-les", "en jouant et en finissant", "des {C:attention}Quêtes{}."},
        es = {"El {C:money}Mercado{} vende cosméticos", "por {C:money}Balacoins{}. Gánalos", "jugando partidas y completando", "{C:attention}Misiones{}."},
    },
    ovt_tip_achievements = {
        en = {"Your {C:attention}Achievements{}! Each one", "shows how to unlock it. Some", "give rewards, so check back", "after a big run."},
        fr = {"Tes {C:attention}Succès{} ! Chacun dit", "comment le débloquer. Certains", "donnent des récompenses, reviens", "après une belle partie."},
        es = {"¡Tus {C:attention}Logros{}! Cada uno dice", "cómo conseguirlo. Algunos dan", "recompensas, así que vuelve", "tras una gran partida."},
    },
    ovt_tip_progression = {
        en = {"Your {C:green}Progression{}: level, XP", "and the rewards on the way.", "Your {C:attention}Quests{} are here too,", "ready to redeem when done."},
        fr = {"Ta {C:green}Progression{} : niveau, XP", "et récompenses à venir.", "Tes {C:attention}Quêtes{} sont là aussi,", "à récupérer une fois finies."},
        es = {"Tu {C:green}Progreso{}: nivel, XP", "y las recompensas por venir.", "Tus {C:attention}Misiones{} también están", "aquí, listas para canjear."},
    },
    ovt_tip_collection = {
        en = {"The {C:attention}Collection{}: every card you", "found. The {C:blue}Multiplayer{} part", "shows the MP jokers, decks,", "stakes and blinds."},
        fr = {"La {C:attention}Collection{} : chaque carte", "trouvée. La partie {C:blue}Multijoueur{}", "montre les jokers, jeux, mises", "et blindes du MP."},
        es = {"La {C:attention}Colección{}: cada carta", "que encontraste. La parte", "{C:blue}Multijugador{} muestra comodines,", "barajas, apuestas y ciegas."},
    },
    ovt_tip_multiplayer = {
        en = {"Welcome to {C:blue}Multiplayer{}!", "{C:attention}Play{} finds a match or a room,", "{C:attention}Ranked{} has fixed rules, and", "{C:attention}Friends{} lets you invite people."},
        fr = {"Bienvenue en {C:blue}Multijoueur{} !", "{C:attention}Jouer{} trouve un match ou un salon,", "{C:attention}Classé{} a des règles fixes et", "{C:attention}Amis{} sert à inviter du monde."},
        es = {"¡Bienvenido a {C:blue}Multijugador{}!", "{C:attention}Jugar{} busca partida o sala,", "{C:attention}Clasificatoria{} tiene reglas fijas", "y {C:attention}Amigos{} sirve para invitar."},
    },
    ovt_tip_cheats = {
        en = {"The {C:red}Cheats{} menu: money, cards,", "jokers and more. A run where", "you use one is marked, so", "it stays apart from your stats."},
        fr = {"Le menu {C:red}Triches{} : argent, cartes,", "jokers et plus. Une partie où", "tu en utilises une est marquée", "et reste à part de tes stats."},
        es = {"El menú de {C:red}Trucos{}: dinero, cartas,", "comodines y más. Una partida", "en la que usas uno queda marcada", "y no cuenta en tus estadísticas."},
    },
    ovt_tip_perf = {
        en = {"{C:attention}Performance{}: each option makes", "the game lighter. Use the ones", "you want, with or without", "Performance mode."},
        fr = {"{C:attention}Performance{} : chaque option", "allège le jeu. Prends celles", "que tu veux, avec ou sans", "le mode Performance."},
        es = {"{C:attention}Rendimiento{}: cada opción", "aligera el juego. Usa las", "que quieras, con o sin", "el modo Rendimiento."},
    },
    sc_sub_settings_search = {
        en = {"{C:attention}Search{}: type a word to find", "any setting in every category,", "then pick a result to jump there."},
        fr = {"{C:attention}Recherche{} : tape un mot pour", "trouver un réglage dans toutes", "les catégories, puis choisis-le."},
        es = {"{C:attention}Buscar{}: escribe una palabra para", "encontrar un ajuste en todas", "las categorías y salta a él."},
    },
    sc_sub_settings_cats = {
        en = {"Settings are sorted in {C:attention}categories{}:", "Gameplay, Shop, Helpers, Controls,", "Display, Audio and more."},
        fr = {"Les réglages sont rangés en {C:attention}catégories{} :", "Gameplay, Boutique, Aides, Commandes,", "Affichage, Audio et plus."},
        es = {"Los ajustes están en {C:attention}categorías{}:", "Jugabilidad, Tienda, Ayudas, Controles,", "Pantalla, Audio y más."},
    },
}

T.STRINGS = {
    fr = {
        ["Tutorials"] = "Tutoriels",
        ["Balatro tutorial"] = "Tutoriel Balatro",
        ["Your first run with Jimbo's tips"] = "Ta première partie avec Jimbo",
        ["Skip Balatro tutorial"] = "Passer le tutoriel Balatro",
        ["The Balatro tutorial is done"] = "Le tutoriel Balatro est fini",
        ["Mark Jimbo's first run as done"] = "Marque la partie de Jimbo comme faite",
        ["Overhaul tutorial"] = "Tutoriel Overhaul",
        ["Hologram shows every Overhaul feature"] = "Hologramme présente tout l'Overhaul",
        ["Open it from the main menu"] = "Lance-le depuis le menu principal",
        ["Skip Overhaul tutorial"] = "Passer le tutoriel Overhaul",
        ["The Overhaul tutorial is done"] = "Le tutoriel Overhaul est fini",
        ["No tour and no Hologram tips"] = "Ni visite, ni conseils d'Hologramme",
    },
    es = {
        ["Tutorials"] = "Tutoriales",
        ["Balatro tutorial"] = "Tutorial de Balatro",
        ["Your first run with Jimbo's tips"] = "Tu primera partida con Jimbo",
        ["Skip Balatro tutorial"] = "Saltar tutorial de Balatro",
        ["The Balatro tutorial is done"] = "El tutorial de Balatro está hecho",
        ["Mark Jimbo's first run as done"] = "Marca la partida de Jimbo como hecha",
        ["Overhaul tutorial"] = "Tutorial de Overhaul",
        ["Hologram shows every Overhaul feature"] = "Holograma enseña todo Overhaul",
        ["Open it from the main menu"] = "Ábrelo desde el menú principal",
        ["Skip Overhaul tutorial"] = "Saltar tutorial de Overhaul",
        ["The Overhaul tutorial is done"] = "El tutorial de Overhaul está hecho",
        ["No tour and no Hologram tips"] = "Sin recorrido ni consejos de Holograma",
    },
}

return T

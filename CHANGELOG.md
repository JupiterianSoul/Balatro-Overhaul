# Changelog

Changelog for the updates, first being the latest changes. 

## 2.1.4

*Overhaul 2.1.4, 2026-11-26. Auto Performance, a steadier frame rate at full quality, modded sessions about twice as fast, a Blue Stake rework toggle, and boot crash fixes.*

### Performance
- **Auto Performance.** On by default in Settings > Performance. When the game can't hold 60 FPS, it lowers effects, card shine, the background and picture sharpness one step at a time, and raises them again when there is room. It never goes above your own settings.
- **Steadier full quality.** The background swirl redraws 30 times a second with the same picture, and the screen effect and menus do less work every frame.
- **Smooth Background.** A new toggle in Settings > Performance brings the swirl back to 60.

### Mods
- **About twice as fast.** Steamodded's own screen shader no longer runs under the Overhaul one.
- **Loading screen mods.** A mod that changes the Steamodded loading screen no longer crashes the start.
- **Clearer clashes.** When several mods break the same file, the error names every mod that could fix it and turns off the one with the fewest changes there first.

### Gameplay
- **Blue Stake rework toggle.** In Settings > Gameplay > Reworks, on by default. Off gives the base game's -1 discard. Daily runs, speedruns and multiplayer keep the standard rules.

### Fixes
- Forge decks and challenges that start with consumables of your own Card Type start with those cards again, not Tarots.
- Modded collection pages like Tags open at normal size on phones again.
- The game no longer stops at start when a language file is broken.
- A Mac or Windows install no longer crashes when Steam isn't running.

## 2.1.3

*Overhaul 2.1.3, 2026-11-19. An easier Forge, animated Jokers with souls and sounds, the last vanilla cards rebuilt exactly, and Forged online with a weekly theme, ratings and remixes.*

### The Forge: easier to use
- **Simple view.** Jokers read as one sentence. Tap any coloured part to change it.
- **Shorter lists.** Pickers show the common options first, with More... for the rest. Long lists have search and groups.
- **Start from any game card.** Every kind can start from a vanilla card, and it keeps its real effect.
- **Sample hand.** A new tab shows what your Joker scores, without starting a run.
- **Clear limits.** Numbers that can't go lower now tell you why.

### The Forge: art and sound
- **Animated Jokers.** A Joker's looks can play as an animation, from 1 to 12 frames per second.
- **Floating soul.** Jokers, Tarots, Planets, Spectrals, Vouchers, Boosters and Enhancements can have a soul that floats like on Legendary Jokers.
- **Sounds.** Every card kind that does something can play a sound when it does, a game sound or your own short .ogg, .wav or .mp3.

### The Forge: vanilla cards
- **The last ones.** The Fool, The Wheel of Fortune, Sigil, Ouija, Ankh, Hex, the Plasma and Erratic Decks, and the Small and Big Blind can now be built exactly.
- **New effects.** "With a chance", "Make the last Tarot or Planet used", "Hand to one random suit", "Hand to one random rank", "Copy a random Joker", "Destroy the other Jokers", "Edition on a random Joker", "Balance Chips and Mult" and "Random ranks and suits".

### Forged online
- **Weekly theme.** Featured is the first tab. A new theme every week, enter up to 3 of your mods, and last week's three best rated lead the list.
- **Ratings.** Rate a mod from 1 to 5 once you've played a run with it. One rating per player, never your own mod.
- **Most played.** New tabs for Best rated and Most played, and each mod shows how many players ran it.
- **Remix.** Press Remix on a mod, online or downloaded, to get its cards in your Forge as your own version. The credit to the original stays with it.
- Creations that use the new features need Overhaul 2.1.3 or later.

## 2.1.2

*Overhaul 2.1.2, 2026-11-19. The Forge can now make your own suits, poker hands, card types, rarities, stickers, challenges and fusions, every creation can be used by your other creations, play solo while the ranked queue searches, Classic Layout on phones, and fixes for 14 crash reports.*

### The Forge: new things to make
- **Your own suits.** Draw a suit symbol, pick an ink colour, and get 13 new cards, 2 to Ace. Flushes count, Tarots and Spectrals can turn cards into it, and Run Info shows it. Suits get full rules too: what they do when scored, held or discarded, "Also counts as" another suit, a rank range, any number of copies in the deck, and a Boss Blind that debuffs them.
- **Your own poker hands.** Pick a pattern (different suits, same suit, in a row, face cards, two groups, every suit and more), how many cards (no limit), which hand it beats and its Chips and Mult. Make its Planet with a Forge Planet. Hands can have their own rules and can stay hidden until played.
- **Your own card types.** A family of cards with a name, a colour and a shop weight, like "Runes" or "Curses". Tarots and Spectrals join a type, packs can hold one, and each type gets a page in the Collection. Types get rules, a fixed sell price (even $0), a Negative chance, a limit on how many you hold, and their own pack art.
- **Your own rarities and stickers.** A rarity like "Epic" with its name, colour, shop odds, price and rules for every Joker of it. Stickers like "Cursed" or "Fresh" with full rules, on Jokers, playing cards or any card, that can peel off after some rounds. A card can hold as many stickers as you like.
- **Your own challenges.** Starting Jokers, consumables, vouchers, money and slots, a starting deck editor, banned cards, packs, tags and Boss Blinds, the game's challenge rules, and any Deck effect. They show up in Play > Challenges, and every game challenge can be a starting point.
- **Joker fusions.** Two or three Jokers (or consumables) fuse into another for a price, with a Fuse button next to Sell. Ingredients can be "any Rare Joker", fusions can keep upgrades and grown values, and a shop card that completes a fusion shows a badge.
- **Everything is linked.** Your Boss Blinds, poker hands, suits, rarities, card types, stickers, stakes, packs, decks and challenges now show up in every list that picks that kind of thing, so what you make can be used by what you make next.

### The Forge: new effects
- **Jokers that grow up.** "Becomes another Joker" turns a Joker into another one, like an egg that hatches into a random Rare Joker after 3 rounds.
- **Looks.** A Joker can have up to 6 pictures and change look as it goes.
- **Boost other Jokers.** Retrigger a neighbour, make it give more, or make it gain Mult, Chips or XMult for good, on vanilla, Forge and mod Jokers.
- **^Mult and ^Chips.** Raise Mult or Chips to a power, with Talisman or Amulet big numbers when they are installed.
- **More moments.** When you earn or spend money, when a card is drawn, before a discard (with "Cancel the discard"), when another Joker is sold, when you get a Tag, a Joker or a consumable, when you beat a Boss Blind, when a new ante starts, when you enter the shop and when a hand levels up.
- **More ways to mess with the run.** Change the Blind score, move the ante, level hands up or down, free rerolls, shop slots, cheaper rerolls, a free card in every shop, debuff cards or heal them, discard drawn cards, draw cards from anywhere.
- **Cards to select.** Play and discard more or fewer than 5 cards, from Jokers, Decks, Challenges, Vouchers, Stakes, Tags, consumables and Boss Blinds. Big hands still find the best poker hand.
- **Losing twins.** "Lose money for each", "-Chips for each" and "-Mult for each". Money can go below $0 like Rental.
- **Free pack.** Decks, Challenges, Stakes, Vouchers, Tarots and Spectrals can open any pack, your own Boosters too.
- **New conditions.** "Any discarded card is" and "All discarded cards are", how much money was earned or spent, how many Jokers of a rarity you have, whether a card has a sticker, and more.
- **Destroy a neighbour Joker.** Now works on every moment outside scoring, like when a consumable is used.
- **Cards that show up when it makes sense.** After a Joker is destroyed, while you own a Joker, or after a poker hand is played.
- **Special effect look.** Give a card the look of Foil, Holographic, Polychrome, Negative or any edition, just for the look.

### The Forge: builder
- **Balance check.** Every creation gets a level, Weak, Fair, Strong, Overpowered or Broken, with a one-line reason. Progress stays on up to Overpowered, only Broken turns it off (asked by Mouse). Every effect is rated, so huge numbers show Broken.
- **Blank.** Blank really starts from nothing, with an empty card to draw on.
- **Published by me.** Your online packs have Update and Remove, and they no longer vanish after an update or between normal and modded play (reported by Mouse).
- **Fixes.** Creations show the real look of suits, hands, types, rarities, stickers and fusions, and Forge Blinds and Stakes show their art in a run.
- Creations that use the new features need Overhaul 2.1.2 or later.

### Multiplayer
- **Play while you wait.** While the ranked queue searches you can continue or start a solo run, and the queue keeps going in the menus, the Training Grounds, replays and while watching a match. When an opponent is found you pick Join or Wait. Idea and bug report by OkiMaSha, thanks a lot!
- **New main menu.** PLAY, MODS and SINGLEPLAYER are the big buttons, RANKED is inside PLAY, and THE CASINO is on the multiplayer menu.
- **Fixes.** Opening a lobby no longer deletes your single-player Continue (reported by OkiMaSha), and PLAY and MODS have the same text size as in the normal menu.

### Gameplay
- **Tally Joker.** Clear labels like Retrigger 2 or +90 Chips, an Advanced setting that says how in a few words, Blueprint and Brainstorm show the copied Joker (or Incompatible), and in portrait the lines fit under your Jokers.
- **Profile icon.** Settings > Gameplay > Main menu has a Reset button that puts the main menu profile icon back in its corner.

### Phones
- **Classic Layout.** A new setting in Settings > Display > Interface brings back the original compact Run Info, tabs and Blind panels in landscape (asked by SmallShape, #48).
- **Portrait shop.** Reroll and Next Round swapped places, so Next Round is harder to hit by mistake.
- **Your suits.** Your own suits share one "Your suits" tab in Customize Deck.
- **Cryptid.** Code card pickers and the Thematic Sets screen work with taps.

### Mods
- **Zip installs.** Add a mod from a zip has a search bar, a Browse button on PC, and you can drop a mod zip on the game window.
- **Fewer crashes.** Profiles Plus, JoyousSpring, Paperback, Betmma Spells and Vouchers, All in Jest, Cryptid with Art Box, Malverk, Rofflatro, QoL Bundle, Pokermon Dip, Sticky Fingers on gamepad, and mods that add buttons to the run HUD.

### Other fixes
- Starting a new run with a card selected, buying the same shop card twice, and a few rare crashes when showing a text or leaving a run.

## 2.1.1

*Overhaul 2.1.1, 2026-11-17. Mods on phones work again after 2.1, no more black screen on the first start, a Forge guide and new Forge deck effects, and fixes for #43, #44, #45 and #46.*

### The Forge
- **Forge guide.** Five short pages explain what a rule is, WHEN / IF / DO, variables, Try it in a run and sharing. It opens the first time you visit the Forge, and the GUIDE button in Creations or Options > Guide > The Forge opens it again.
- **Cards always come with.** A new deck effect: give every Joker, playing card, Tarot, Planet, Spectral, Voucher, Booster pack, or everything, an edition, an enhancement or a seal, with a chance and an option to replace what is there. A deck can have several, like every Joker Polychrome and every card Negative.
- **Always comes with.** Jokers, Tarots, Planets, Spectrals and Enhancements can start with an edition, and Jokers can put an edition on a random Joker that has none.
- **Variables in numbers.** Every number box of a rule can use a variable: press Variable next to Type and pick one. The card text shows its value right now.
- **This round's suit.** A new condition for rules that run when a hand is played: the hand has a scoring card of this round's suit.
- **Fixes.** Green Joker loses 1 Mult per discard like the real one, the Tarot and Planet Merchant and Tycoon recipes match the game, and a rule that destroys a card and creates one now swaps them even when your Joker row is full (#46).
- Creations that use the new features need Overhaul 2.1.1 or later.

### Gameplay
- **Negative playing cards.** They give +1 hand size while you hold them, like with Steamodded.
- **Tally Joker.** A Joker with a long text no longer blocks the Select button under the Jokers (#45).

### Phones and start
- **No black screen.** The first start after installing or updating shows a progress bar while the game gets ready.
- **Start errors.** If the game fails to start, it shows the error with Copy and Discord buttons instead of a black screen.
- **Mods after updating.** Every modded game crashed at start after updating to 2.1, and touch stopped working. Fixed (#43).
- **Music mods.** Mods like Balatro Takanaka no longer start the song over before it ends.

### Mods
- **Fewer crashes.** Lost Edition, Paperback, Galdur, and Sagatro with cartomancer.
- **Continuing a run.** Continuing a run after turning on a mod like Cryptid no longer crashes when you beat the first Blind.
- **Updating a mod.** Updating a mod while the game is open asks you to restart, so its new features load.
- **Talisman.** Every Overhaul change applies again with Talisman.
- **Zip installs.** Mods installed from a zip no longer miss files with two dots in their name (Wormhole). Install the mod again to get them.

### Multiplayer
- **Only vanilla decks.** "Only vanilla" in Decks to pick from now applies to the ranked deck draft, the lobby deck and random decks, for both players (#44).
- **Fixes.** A crash after Cash Out when a PvP result arrived late, and the "server restarted" message that stayed on screen over menu buttons.

### Other fixes
- A crash when viewing your deck with a Forge Enhancement that has no rank, and when pressing Start on a controller during the splash screen.

## 2.1

*Overhaul 2.1, 2026-11-16. iPhone and iPad, mods that work like on PC, Tally Joker, an edition editor and a lot more in the Forge.*

### New features
- **iPhone and iPad.** Install the app with AltStore or SideStore (it's not on the App Store), then import your own Steam `Balatro.exe` from the Files app: it gets patched on the device, like the Android app made from Steam. Ported by [JohnG210](https://github.com/JohnG210), thanks a lot!
- **Mods work like on PC.** Overhaul now keeps Balatro's own files and the official Steamodded untouched and applies its changes after your mods, so mods see the same game as on PC. Many mods that crashed or misbehaved with Overhaul now just work.
- **Tally Joker.** During a run, a line under each Joker shows its current value and its chances. When you pick cards, it shows what the Joker adds to that hand and how many times it retriggers. Works with every Joker, modded and Forge ones included. Turn it off in Settings > Helpers.
- **Mouse wheel keys.** In Keyboard keys, the mouse wheel can be mapped, for example Play on wheel up and Discard on wheel down. In menus the wheel still scrolls.
- **In-game keyboard setting.** In Settings > Controls: off by default on PC, on by default on phones. When it's off, every text field uses your own keyboard.

### The Forge
- **Edition editor.** Start from any edition in the game, the 4 classic ones and the 12 Overhaul shines (Hologram, Prism, Spectral Glow...), and pick its shine, colour and strength with a live preview. What you draw for an edition now shows on every card that has it. Editing a game edition makes your own copy.
- **XChips.** Jokers can multiply your Chips, and XChips works on every kind of creation.
- **Downsides.** Jokers can lose money, give -Chips or -Mult, divide Mult, take away hands or discards, or make the current Blind bigger.
- **Variables.** They can hold a suit, a rank, a poker hand, an edition, an enhancement or a seal, not only a number, and "Set a variable" can pick a random one.
- **New rules.** "Every N times" (like Yorick), make a Joker with a chosen edition, draw cards, copy a random Joker, count cards or Jokers with an edition, and booster packs that put one edition on every card.
- **Card text.** The text editor is now one free text box: type with your real keyboard, Return starts a new line, and you can paint words in any colour.
- **Try it in a run.** The pause menu has Back to the Forge, which takes you straight back to the builder on the same creation.
- **Builder.** The settings line up in even columns, every rule can be removed, editions can have no shine, and the pixel editor has a Replace colour tool (key C) and a Save button.
- **Fixes.** Your vouchers on a custom deck work from the start of the run, your vouchers and booster packs work with Cryptid, Tag art shows everywhere, your vouchers sit in pairs in the Collection, and "ERROR in 7" is gone.
- Creations that use the new features need Overhaul 2.1 or later.

### Mods
- **Fewer crashes.** Frost_Utils, Maximus, Spectrallib and Cryptid.
- **Big numbers.** With Talisman or Amulet, "Score reached", Jimbo's comments and the best hand finder work again.
- **Custom Run.** "No boss blinds", "Showdown bosses only" and turning off card types in the shop now work with mods.
- **Mod stakes.** Overhaul's extra stake effects no longer pile onto a mod's own stakes, and wins on them count as Gold Stake wins.
- **With mods.** Card sleeves and ranked cosmetics show on cards, Forge editions show up in runs, the phone vibrates when a hand levels up, and Forge Tags and Blinds you turned off stay hidden.
- **Forge rules.** With mods, rules on cards and decks score once per card again (they could apply several times).
- **Smoother.** Less work every frame with Steamodded.

### Phones
- **Texture packs.** Malverk packs can be turned on: tap a pack, then Apply.
- **Shop.** Tap any card to get the same buttons as on PC, also for cards mods put in another row (#38).
- **Right click for mods.** A long press works as a right click for mods that use one, like Saturn.
- **Landscape with mods.** The Blind choice no longer cuts off long boss texts.
- **Crash fixes.** At start on some Android phones, at the title screen with mods, and when leaving the shop while the screen changed size.
- **Small fixes.** The "1 in 7" of The Wheel in Run Info has the right size, and the Settings search opens the right page.

### Multiplayer
- **Decks to pick from.** Now on the Players tab of the lobby, next to Deck.

### Fixes
- **Slowdown.** The game no longer gets slower the longer you play with Jokers.
- **Score preview.** The hand name stays visible and long scores shrink to fit (#39).
- **No more flashing.** Windows that refresh no longer jump to the top left first.
- **Replays.** A crash when a replay recording stopped is fixed.

If you already have the Overhaul, update from the launcher or the Update button on the title screen.

## 2.0.7

*Overhaul 2.0.7, 2026-11-15. A redone New Run, Run Modifiers, Advanced mode for every Forge creation, faster modpacks, and much bigger text on phones.*

### New features
- **New Run.** It's redone: you pick your deck, then your Run Modifiers, then your stake, then play. Each deck shows its effect and how to unlock it, each stake shows what it adds, and there are Random, Last Run and Seeded buttons.
- **Run Modifiers.** Add the effects of any other deck to your run, or turn off single stake effects. Runs with modifiers don't count for unlocks, stake wins or achievements. In multiplayer, the host can turn them on for the whole lobby.
- **Advanced mode for every Forge creation.** Rules and variables now work for every kind of creation, not just Jokers: enhancements, seals, editions, Tarots, Planets, Spectrals, tags, vouchers, decks, stakes and blinds. For example, a card can now gain Mult each time it scores.
- **New rule conditions and effects.** Dozens of them: first scoring card, hand contains a suit or rank, most played hand, Mult or money per Joker, per card in your deck or per dollar, random Mult, Jokers of a rarity, and more.
- **Passive Joker effects.** Forge Jokers can change hand size, hands, discards, slots, interest and rerolls, work like Four Fingers, Shortcut or Splash, copy other Jokers like Blueprint and Brainstorm, and prevent a game over like Mr. Bones.
- **Remake the base game.** Every Joker, enhancement, seal, edition, voucher, tag and Boss Blind of the base game can now be remade in the Forge.
- **Your creations work everywhere.** Your own enhancements, seals, editions and tags work everywhere the base game ones do. Effects can create a specific card instead of a random one, decks can start with specific cards, packs can contain only the cards you choose, and tags can give a voucher.
- **Game speed.** New x3 and x5 speeds, and a custom speed you type yourself (0.5 to 100).
- **Deck filter.** New option in Options > Gameplay: show only vanilla decks, only new decks, or both.
- **Neon Orchid.** A new legendary palette in the Tailor.

### The Forge
- **Forge mods.** They now include everything their creations use, so they keep working after install and in Forge rooms.
- **Builder.** Long button names wrap, deleting a creation shows what uses it, you get a warning before a name is cut or rules past 12 are removed, the Variables tab explains what variables are, and your own stakes can be picked in New Run.
- **DNA.** "Copy the card" can put the copy in your hand, so DNA can be remade exactly.
- **Fixes.** "When playing cards are destroyed" triggered after every hand, "When you buy a card" triggered twice, the poker hand condition didn't work on discards, Foil counted custom editions, names with accents were cut, and custom editions crashed modded games.

### Mods
- **Card Sleeves.** It works again, and you pick your sleeve in New Run.
- **Faster loading.** Big modpacks load much faster (Pokermon: 21 s down to 8 s). Restart now in the Mods menu really restarts the game instead of freezing on "Loading Cloud save...".
- **Crash fixes.** Cryptid (code cards, Wormhole deck), Kino, MLP and mahrlatro.

### Phones
- **Bigger everything.** Much bigger text, cards and buttons on almost every screen, in landscape and portrait. In landscape, menus use the full width of the screen.
- **Multiplayer screens.** The lobby has two columns in landscape, and Ranked, Friends, Alerts, Lobby Info, spectating and match results have bigger text.
- **UI Size.** Your phone keeps its own UI Size, so a save from PC no longer makes every menu tiny.
- **Portrait fixes.** Pop-ups fit on screen, badges and emotes no longer cover the blind name or "Opponent disconnected", the cash out panel and Settings tabs fit, and modded Boss Blinds with long descriptions are no longer cut.
- **Screen Orientation.** It now checks that the screen really rotated. If it didn't, a message tells you how to fix it, with a Try again button.

### Multiplayer
- **Ranked down.** The game now tells you instead of failing silently.
- **Reworks tab.** Lobby Info now shows what each rework changes (it showed "#1#" for Investment Tag).

### Launcher
- **Old app.** If your app was made by an older launcher, the launcher now shows REBUILD THE APP as the main button.

### Fixes
- **Wild Card.** Its "Immune to Boss Blind debuffs" line is now translated in every language.
- **Linux.** Pick a file and Open the folder work again.

If you already have the Overhaul, update from the launcher or the Update button on the title screen.

## 2.0.6

*Overhaul 2.0.6, 2026-11-13. Pick your deck and jokers in multiplayer, rejoin a match, one Mods switch, and lots of fixes.*

### Multiplayer
- **Pick screen.** When a match starts, everyone picks their deck and up to 5 Common or Uncommon jokers. It comes back before every rematch with your last picks.
- **Deck draft.** Ban decks in turns, then pick from what's left. Bots ban and pick too, and really play what they get.
- **Rejoin.** Lost your connection? Come back within 15 minutes and the match picks up where it was.
- **New lobby options.** Random deck, Random stake, and Boss effect on PvP, so the PvP blind carries a real boss effect. Every setting now says what it does.
- **Bots.** They never leave a match anymore, think at normal speed again, and Medium bots shop properly.
- **Rooms.** A closed room offers you a new one, a room whose host left says so, rooms take up to 50 Forge mods, and the PvP countdown works again.

### Mods
- **One Mods switch.** It replaces PLAY WITH MODS and MODDED COLLECTION. Flip it, press Restart now, and the game tells you why it needs a restart. Your ticked mods are kept for next time.
- **MODDED / NORMAL badge.** You always see which game you're in, on the title and during a run. Tap it on the title to open the Mods screen.
- **Rejoin with mods.** Rejoining a modded match after turning your mods off turns them back on.
- **Faster and safer.** Talisman and Amulet start about twice as fast, Cryptid's vouchers and decks work again, big hands no longer freeze the game, and Boss Blinds show their description again.
- **Fixes.** Bunco no longer flips the stake list, Cartomancer no longer hides the MULTIPLAYER text, and the Collection shows Tarot, Planet and Spectral cards again with mods on.

### Phones
- **Orientation.** With auto-rotate off, the game follows your phone's lock, and Portrait or Landscape in Screen Orientation always wins. Press REBUILD THE APP once to get it.
- **PC-style selection.** A new Gameplay setting: tap a joker or consumable to select it, so cards that target a joker work, like Cryptid's Code cards.
- **Sizes.** Pop-ups and small windows are the same size in portrait and landscape, and the run HUD grows with UI size above 100.
- **Fixes.** The deck count table no longer sticks over your hand, and a joker lifted with a pen goes back down when you tap it.

### Launcher
- **Updates itself.** A new launcher downloads in the background and is used on the next start. On phones it offers UPDATE THE LAUNCHER when the app needs it.
- **Windows updates.** Updating from the in-game Update button no longer fails with "Is the disk full?".

### Everything else
- **New Run.** Tap the deck or the stake to see them all in a grid.
- **Tailor.** Every category has a Random card: you get a new look each game, and you can ban the ones you don't want.
- **The Forge.** Creations can make a Random Tag, the Starts at arrows go faster when held, and the score preview counts voucher and deck bonuses.
- **Drag to Select.** Pick which mouse button drags, right or left.
- **Fixes.** About 15 crash fixes from your reports.

If you already have the Overhaul, update from the launcher or the Update button on the title screen.

## 2.0.5

*Overhaul 2.0.5, 2026-11-12. A big one: phones, the Forge, saves and lots of fixes.*

### Phones
- **Portrait and landscape.** Every screen now works and reads well both ways, and turning your phone keeps you where you were. If auto-rotate acts up, pick one in Settings > Display > Screen Orientation.
- **Bigger UI.** Boss Practice got a new look, and the small stuff in portrait (pause menu, Forged list, achievement pop-ups) is bigger.
- **Touch.** Tapping a selected card unselects it straight away, and a quick tip plus a new Guide page show how to swipe over cards.
- **Pixel editor.** Your pencil now draws right under your finger.
- **Keyboard.** Lowercase letters, numbers and symbols are in.
- **Your files.** The game folder now shows up in your phone's file picker, so you can reach your mods, saves and pictures.

### The Forge
- **Any value you want.** Every number can be set freely, just type it or hold the arrows.
- **Way more to make.** Lots of new effects for every kind of card, and you choose when each one triggers.
- **Vouchers.** Yours can show up in the shop right away, or only after another voucher is bought.
- **Easier to use.** A Simple / Advanced switch, Back takes you one step back instead of kicking you out, and you can pick pictures and Forge mods straight from your files.
- **Multiplayer.** Forge mods work in private rooms, and friends who don't have them get them from you in one tap.

### Saves
- **Import and export.** One simple button for each, in the game and the launcher. You see the save before importing it, and yours is always backed up first.
- **Collection reset fixed.** Importing a save and then playing with mods no longer looks like your collection got wiped.
- **No more lost progress.** Closing the game while it saves won't reset your profile, and Talisman/Amulet saves load properly again.

### Fair play
- **Progress only counts for real runs.** Replays, cheats, Forge cards and Forge test runs don't give achievements or XP anymore.
- **Like the original.** New profiles start with the same locked cards as Balatro, and Unlock All behaves like it does there.
- **Cleaner collection.** Multiplayer jokers and blinds don't show up in the solo collection anymore.

### Mods
- **Safer mods.** Mods can't mess with files outside the game anymore, and you're asked before turning on one that isn't from the Workshop.
- **Clearer crashes.** If a mod breaks the game at start, it tells you which one and only turns that one off.
- **Fewer crashes.** Cryptid, Paperback and other popular mods crash less, and switching mods on or off mid-run is fine now.

### Everything else
- **Replays.** The controls stay out of the way, and you get a proper end screen when it's over.
- **Bot-latro.** A smarter bot, and Easy actually makes mistakes again.
- **Gameplay.** Matador is back to the original, and Blue Stake now raises shop prices instead of taking a discard.
- **What's New.** You'll see what changed after each update, and there are Discord and GitHub buttons on the menu.
- **And more.** The Tailor works with taps again, Workshop downloads retry on their own, and around 40 crash fixes.

If you already have the Overhaul, update from the launcher or the Update button on the title screen.

## 2.0.4

*Overhaul 2.0.4, 2026-11-11. The security update, downloads are back.*

- **Security.** The part of the game that could run commands on your PC is gone. It was used to install mods and manage files, and a modded multiplayer room could have abused it. Steamodded doesn't call git anymore, and the Windows launcher makes its shortcuts with a plain, visible command.
- **Security.** Saves, and runs you get from other players, are now read as plain data, so they can't run anything. An imported save zip can only contain save files.
- **Security.** Mods only work in private rooms now, and only mods from the Workshop can be used online. Public rooms, Quick Match and public parties are the normal game.
- **Mods.** The game doesn't install zips from your Downloads folder by itself anymore, you pick the one you want. There's also a safe mode: if a mod breaks the start, the game starts without mods next time, and both launchers have a Mods tab to turn a mod off or remove it.
- **Mods.** A lot of popular mods work again (Paperback, All in Jest, Galdur, Talisman, Deck Creator, Cardsauce, Betmma's mods...). Mods we played through a full run get a green TESTED badge in the Workshop.
- **Android.** The game doesn't ask for file access anymore. Adding a mod or music opens Android's own file picker, and you can export and import your save from the phone.
- **Android.** Fixed the phone launcher crashing on start, the app now opens straight into the game, and phones on Android 5 and 6 can install it. Balatro made with Balatro Mobile Maker works as the base game too.
- **Touch.** Swipe over cards to select them, tap a card again to close its info, double tap to play. Thanks to bshurikan for the PR!
- **Other.** Controller icon picker (Xbox, PlayStation, Switch) for pads detected as the wrong brand, the portrait shop fits more than 5 cards, and your first modded profile starts as a copy of your normal one.

If you already have the Overhaul, update from the launcher or the Update button on the title screen.

## 2.0.3

*Overhaul 2.0.3, 2026-11-10.*

- **Multiplayer.** The ONLINE / OFFLINE label in the menus now really checks the server. It used to say OFFLINE everywhere outside a lobby or a match, even when the servers were up.

## 2.0.2

*Overhaul 2.0.2, 2026-11-10.*

- **Credits.** Steamodded, Balatro-DeckCreator and Cryptid are now credited in the game, and the licence and third-party notices come with the game and the downloads. The Overhaul's source code is public under the GPL v3.
- **Version.** The build number now shows next to the version, for example 2.0.2 b55.
- Removed the Joker Info overlay, at its author's request.

## 2.0.1

*Overhaul 2.0.1 (pre-release), 2026-11-09.*

- **Credits.** The multiplayer is based on [Balatro Multiplayer](https://github.com/Balatro-Multiplayer/BalatroMultiplayer) by Virtualized and the BMP team. They are now credited in the game's Credits screen and in About.
- **Android.** Fixed the black curved area that could cover part of the screen on some phones, such as the Pixel 9 Pro.
- **Android.** The phone app works with any Balatro APK (normally, can have issues, this is a fast patch)

## 2.0

*Overhaul 2.0 (pre-release), 2026-11-08. The first public release, so this is everything the Overhaul adds to Balatro.*

### The big ones

- **Multiplayer.** Play online in 1v1 or in parties of up to 8, against friends, random players or bots, casual or ranked. Quick Match, public or private rooms with a 4-letter code, a room browser, and your seat is kept for 15 minutes if you disconnect.
- **The Forge.** Make your own jokers, tarots, planets, spectrals, vouchers, enhancements, seals, editions, tags, blinds, stakes, decks and booster packs. Draw their art in the pixel editor, use them in your runs and share them online.
- **The Casino.** A new map with eight places: the Tavern, the Market, the Tailor, the Forge, the Library, the Training Grounds, the Arcade and the Racetrack.
- **Progression.** XP and 100 levels over 7 ranks, daily and weekly quests, Journeys and over 200 achievements. Levels and quests pay Balacoin, which you spend in the Market.
- **Integrated Mods support.** Workshop with almost all existing Balatro mods, working for Mobile and PC. 

### Multiplayer

- **1v1 modes.** Rivals: boss blinds are PvP from ante 2. FaceOff: every blind is PvP. Ascension: no PvP, the furthest round wins. Race: first to clear the target ante wins. Switcheroo: after each boss blind you trade runs with your opponent (deck, jokers, money, everything but your lives), after a ready screen and a 3 second countdown.
- **Party modes.** Battle Royale: the lowest scores on each PvP blind lose a life, last one standing wins. Teams: teams of 2 to 4 add up their scores and share their lives. Co-op Raid: everyone scores against one shared boss, with shared lives and a bonus for the top scorer. Race also works with more players.
- **PvP blinds.** Both players play the same blind and the higher score wins. The loser loses a life, and with no lives left the match is lost. Parties have their own blinds: Royale Blind, Team Clash and Raid Boss.
- **Ranked.** Rivals with fixed rules and a deck draft where each player bans 2 of 5 decks. 10 ranks from Stone to TRUE JIMBO, with 3 tiers each. Seasons every three months, with a soft reset and a season badge and sleeve for your peak rank. Ranked XP opens packs of titles, sleeves, card and joker frames, flames, bursts and celebrations.
- **Daily and Weekly.** A multiplayer challenge with rules, a deck and a seed picked by the server, one or two random modifiers, and a leaderboard.
- **Room settings.** The host picks the lives, the ante PvP starts at, the final ante, the deck (or lets each player pick one), the stake, the seed, timers, free timeouts, life steal, a PvP win bonus, comeback money, a hidden enemy score, a shared shop queue, banned cards and any custom run rule. Settings can be saved in 3 preset slots.
- **Rulesets.** Ready-made rules for each mode: Classic, Balanced, Vanilla, Slow burn, Tournament, Scarcity, Sprint, Chaos, Quick duel, Rapid fire, Marathon, Glass cannon, Sudden death, Bloodbath, No carry and Heroic.
- **Modifiers.** Layers the host can stack on any match: three clock speeds, sturdy or fragile Glass cards, Inflation, No interest, Discard tax, Frugal, Spartan, a bigger or tighter shop, Mystery prices, Shared pockets, Unstable score, No red seals, No gambling, Scarcity, Face down cards and Eternal jokers.
- **Traps.** Trap Packs in the shop let you set one of 12 hidden traps on your opponent. For example Tollbooth makes their rerolls pay you, and Bear Trap makes the next joker they buy Rental. Up to 3 traps can wait on one player.
- **Multiplayer jokers.** 20 jokers that only exist in multiplayer, like Truce, Grudge, Mirror Match and High Roller, and jokers made for Ascension, Race, Battle Royale, Teams and Raid.
- **Decks and stakes.** Lilac, Seer, Tangerine, Cobalt, Gemini and Random decks. The Random deck gives each hand random Chips and Mult and shuffles prices, card values and packs, with a chaos slider. Three multiplayer stakes: Nova, Eclipse and Eclipse+.
- **Reworks.** Some rulesets change a few base cards: Hanging Chad, Bloodstone, Glass cards, Golden Ticket, Seltzer, Turtle Bean and Ouija. The room and Collection > Reworks show which ones.
- **Friends and chat.** Friends list with online status, invites and Ask to join, private messages, lobby chat that keeps working during the run, 12 emotes, mute, report and block. Chat asks your age once and is for players 13 and over. Duplicate cosmetics can be sent to friends as gifts.
- **Replays and spectating.** Finished matches are saved as replays you can pause, speed up and skip through. Watch public or friends' matches live, or watch the others once you're done with your hands.
- **Bots and modded rooms.** The host can add Easy, Medium or Hard bots. Rooms can use mods (beta): they list their mods and the missing ones install when you join.

### Solo

- **4 new stakes.** After Gold Stake. Chaos: booster packs offer one fewer choice. Apocalypse: Boss Blinds also debuff a random suit. Oblivion: a random joker is debuffed each blind. Transcendent: every Boss Blind is a finisher. Each one keeps the stakes below it, raises the winning ante by one (10 to 13), and has its own sticker.
- **Custom runs.** Set your own rules in 8 categories: basics, economy, blinds, shop, deck, items, bans and fun. Hands, discards, hand size, slots, money, interest, blind size, shop odds, deck size from 1 to 208 cards, starting jokers and vouchers, banned cards, a number randomizer and more. Save your rules as presets.
- **Random runs.** A random deck and stake, or a Custom random run with random rules you can read before you start.
- **Daily run.** The same seed for everyone each day, with 2 twists, 1 boon and a starting joker. One scored try per day, a streak, and a leaderboard with a Friends tab.
- **Speedruns.** Ante 2, Ante 4 and Any% categories, on a weekly seed or random seeds. A timer with ante splits, personal bests, an online leaderboard and replays of the best runs.
- **New challenges.** 10 new challenges: Bankruptcy, The Gauntlet, Tiny Hands, Heavy Hitter, Glass Cannon, The Collector, Wildcard, Speed Run, The Alchemist and Duality.
- **Boss Practice.** Fight any boss you've met, with the deck and loadout you want, even one taken from a past run. No rewards, and nothing goes into your stats.
- **Run history.** Your last 200 runs with their seed, deck, stake, best hand and final jokers. Play the seed again, or watch a replay of any of your last 50 runs.
- **Seed Library.** Save seeds with their deck and stake, or paste one, and play them later.
- **Boss badges.** Beat a boss 10, 15 or 20 times to earn its badge and a title. Equip a badge and that boss's effect is turned off in your next run.
- **Deck Creator.** Make your own decks: rules, money, shop odds, exactly which cards are in the deck, starting items and twists. Share them as a text code.
- **Cheats.** Turn them on before a run, then use the Cheats button (you can drag it anywhere) to add jokers, cards, consumables and vouchers, level up hands, change money, hands and slots, or win the blind. A run with cheats gives no progress.
- **Stats.** Solo and multiplayer stats: wins, streaks, best hand, highest ante, time played, results per deck and stake, and your favourite jokers and hands.

### The Casino

- **Market.** Spend Balacoin on packs of cosmetics: Palette, Jester, Sleeve, Shine and Title packs, Jumbo packs, and the Tavern and Legend Crates. Every odd is in the Odds tab, items you don't have are 3 times more likely, duplicates turn back into Balacoin, and Legend Crates give a Legendary at least every 40 cards.
- **Tailor.** Equip your cosmetics: profile icon and its shine, title, colour sets, table felt, card backs in 5 finishes, score flames, celebrations, portraits and Jimbo skins.
- **Arcade.** 10 minigames: High or Low, Joker Memory, Name the Hand, Find the Ace, Blackjack, Whack-a-Joker, Slot Machine, Beat the Blind, Jimbo Run and Jimbo Jam, a rhythm game that can play any song from your Jukebox. Each one keeps your best score, and you can play them while you wait in multiplayer.
- **Inside the Forge.** Joker rules are built from 20 triggers, 23 conditions and 26 effects, with variables. The pixel editor has drawing, shape and selection tools, a soul layer and picture import. Export creations as a .forgemod file, publish them online, or let your whole room play with them.
- **Quests and achievements.** 4 daily quests (one free swap a day), 4 weekly quests, and 24 Journeys with 3 to 5 stages each. Achievements have popups, rarities, and give titles, badges and cosmetics.

### Mods

- **Normal and Modded.** Two separate games, switched from the title screen. Normal never loads mods, Modded loads yours. Each one has its own 3 profiles, so mods can't touch your main saves.
- **Mod support.** Most Steamodded and Lovely mods work, on Android too. The Mods menu turns them on and off, opens their settings, updates and removes them. A mod .zip in your Downloads folder installs at startup. If a mod crashes the game at startup, the next start turns it off and tells you which one it was.
- **Workshop.** Browse, search and install mods from the Balatro Mod Index without leaving the game. Required mods are installed for you, and each mod says if it works on your platform.

### Everything else

- **Launcher.** For Windows, macOS, Linux and Android. It finds your Balatro (Steam, the Xbox app, Flatpak), builds the Overhaul from it, brings in your Balatro progress or starts fresh, backs up your saves and adds shortcuts. On PC it can also make an Android app from your Steam copy.
- **Updates and saves.** The game and the launcher tell you when there's an update and install it, and your saves stay. Export all your profiles as one .zip and import them on another device. A backup is made before any import.
- **Controls.** Full controller support with rebinding and slide select, a whole run playable on keyboard with rebinding, touch on PC and phone, a trackpad mode, and a cursor speed setting.
- **Helpers.** Score preview, joker info under each joker, Jimbo commenting on your run, drag to select, total sell value, quick restart, interest guard, safe sell, fast packs, a speed key up to 20x in solo, mute keys, pause when you tab out, and a settings search.
- **Jukebox.** Play your own music instead of the soundtrack. Put mp3, ogg, wav or flac files in the My Music folder, or let the game find them in Downloads.
- **Display and performance.** A performance mode, plus separate options for sharpness, background, card shine, particles and frame rate. Colour filters, an FPS counter, UI size, and Fill the screen on phones in portrait.
- **Languages.** The whole Overhaul is in English, French and Spanish.

### Changes to the base game

- Blue Stake: instead of -1 discard, shop items cost $1 more per ante cleared and rerolls go up by $2. Higher stakes keep it, except Nova and Eclipse.
- Wild Cards can't be debuffed by Boss Blinds.
- Matador gives $2 for each discard used during a Boss Blind.
- Death and the other cards with raised values work above their normal value.
- A blind you already beat can't be played again.
- The title screen has a What's new window, and About has the changelog, credits and a Patreon link.
- Crash reports are on by default. They send the error, the version, your platform and your mod list. Turn them off in Settings > Account.

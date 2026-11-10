# Multiplayer protocol: drops, rejoin, match end, results screen

This covers what changed for reconnection (NEXT.md item 6), clear end reasons (item 2) and the results screen (item 4). Everything else in the protocol works the way it did before. Messages are JSON over the WebSocket; `C -> S` means client to server, `S -> C` server to client.

## The short version

- Each seat in a room has a session token. Keep `{code, token}` on disk for the length of a match.
- During a match, a dropped socket, `return_to_menu` or `leave_lobby` does **not** end the match. The server holds it for 15 minutes and tells the other player.
- The player who stayed can wait or send `leave_match`. Leaving ends the match for good.
- The dropped player checks with `check_rejoin` from the menu and comes back with `rejoin_match`.
- Every match end sends `match_ended` with a reason from the receiver's point of view. Every room close sends `room_closed` with a reason.
- On the results screen only the host can `return_to_lobby`, and it brings both players back.

## Rooms, browsing and mod sets

Protocol version 7 (`MP_PROTOCOL_VERSION`). Quick Match is gone from the menu; players create rooms and browse them. `find_match` still works on the server for old clients.

### Mod sets

`create_room`, `join_room`, `find_match` and `list_rooms` take an optional `mods` list:

```
mods: [{ id, name, version }]      id and name 1 to 64 chars, version up to 32, at most 100 entries
```

Leave it out (or send an empty list) for the normal game. The modded game sends every mod that is loaded; with the Steamodded fork running and no mod (test setups only) it sends `{ id: 'Steamodded' }`. The server sorts the list by `id` and keeps `id@version` pairs as the fingerprint. A socket keeps the last list it sent, so later messages can leave it out.

A room takes its host's mod set. Joining needs the exact same fingerprint: vanilla with vanilla, or the same mods at the same versions. Quick match only pairs players with the same fingerprint.

### Game version

The same four messages take an optional `version`: the Overhaul version (`OVERHAUL_VERSION` in `assets/globals.lua`, 1 to 32 chars). A socket keeps the last one it sent. A room takes its host's version and only players with the exact same version can join (`room_error { reason: 'version_mismatch', hostVersion, yourVersion }`); the version is checked before the mod set. Quick match only pairs the same version. A client that never sends one counts as version `''`. Bump `OVERHAUL_VERSION` on every release that changes the game or the protocol.

### Player names

`create_room`, `join_room` and `find_match` take `name` (up to 32 chars); `player_name` still works. The server trims it and squeezes spaces, then refuses:

- a default name: empty, `P`, `P1`, `P2`..., `Player`, `Player 1`..., `M1` to `M9`, `Opponent`, `You` (any case);
- a name already used (case does not matter) by another connected socket, or by a player whose seat is held during a match.

```
S -> C  name_refused { reason: 'default' | 'taken', name, for }      for = the refused message type
```

Nothing else happens on a refusal (no room is created or joined; `player_name` keeps the old name). The client asks for another profile name and retries. A message without `name` claims nothing (old clients and tests); the room shows "Player 1" / "Player 2". A socket's name is freed when it closes.

### Create

```
C -> S  create_room { visibility?: 'public' | 'private', mods?, version?, name? }
S -> C  room_created { code, id, visibility, modded, version, playerId: 0, token }
```

`visibility` defaults to `private`. `name` is the host name shown in the room list (see Player names); `player_name` updates it later. A socket already in a room gets `room_error { reason: 'already_in_room' }`. `id` is the room's 12 hex character browse id. The client goes straight to the lobby; a private room shows its code there, a public one shows "Public room".

### Browse

```
C -> S  list_rooms { mods?, version? }
S -> C  room_list { rooms: [entry], total, at }
```

Every room with at least one connected player, newest first with joinable rooms on top, at most 60. The caller's own room is left out. An entry:

| Field | Meaning |
|---|---|
| `id` | Browse id, used by `join_room { id }` |
| `name` | Host name (the client shows "<name>'s room") |
| `players`, `maxPlayers` | Seats taken (held seats count, in a lobby too) and seats in total (2 for now) |
| `private` | The code is needed to join; it is never in the list |
| `modded`, `mods` | The host's mod set |
| `sameMods` | The caller's mod set matches the room's |
| `inMatch`, `full` | Why the room cannot be joined |
| `joinable` | Lobby with a free seat, the host connected and the same game version as the caller |
| `version`, `sameVersion` | The room's game version, and whether it is the caller's |
| `ping` | The host's last reported round trip to the server in ms, or null |
| `mode` | The room's game mode key from its lobby settings (`attrition`, shown as Nemesis, until the host picks another) |

Ping: clients send `ping { rtt? }` right after connecting and then every 25 s, where `rtt` (integer ms, 0 to 60000) is the round trip of their previous ping. The server stores it and answers `pong`. The browse window adds the caller's own round trip (time to get `room_list`) to the host's and shows 3 bars (under 150 ms), 2 (under 300 ms) or 1.

### Join

```
C -> S  join_room { code } | { id } | { id, code }, mods?, version?, name?, token?
S -> C  room_ready { code, id, host, playerId, token, visibility, version, rejoined, settings?, hostName? }
S -> C  room_error { reason, id?, ... }
```

`join_room { code }` works for any room. `{ id }` joins a public room; a private one also needs its `code`. The guest's `room_ready` carries the room's current `settings` and `hostName`, since the host can change settings before anyone joins. The host also gets `room_ready` (with `host: true`) and stays in its lobby.

`room_error.reason`:

| Reason | When |
|---|---|
| `invalid_code` | No room with this code, or the code does not match the private room `id` |
| `code_required` | `{ id }` of a private room without a code |
| `room_full` | Both seats taken |
| `in_match` | A match is running or on its results screen |
| `room_gone` | Unknown `id`, or nobody is connected to the room |
| `already_in_room` | The socket is already in a room |
| `version_mismatch` | Different game version; also has `hostVersion` and `yourVersion` |
| `mods_mismatch` | Different mod set; also has `hostModded`, `hostMods` (exact ids, names, versions) and `yourMods` |

On `mods_mismatch` the client shows the host's mods and asks to install them. Yes calls `ModWorkshop.install_required(mods, cb)` (mods without the `Steamodded` entry), enables exactly those mods, writes `mp_pending_join.txt` (`{ id, code, private, at }`) and switches to the modded game; the next title screen joins the room again (within 15 minutes). A modded player refused by a vanilla room gets the same with "switch to the normal game". Without `ModWorkshop` the client says "Install these mods first."

### A guest leaves the lobby

Before a match starts (or back in the lobby after one), a guest leaving (`leave_lobby`, `return_to_menu`, `leave_match` or a closed socket) keeps the room and holds the guest's seat for 15 minutes (the rejoin hold). The host gets:

```
S -> C  guest_left { reason, code, held: true, secondsLeft, holdSeconds }      reason: opponent_left | opponent_disconnected
```

The room stays full: nobody else can join (`room_full`) and Browse shows it as 2/2. Settings and game history are kept. The guest comes back with `join_room { code or id, token }` using the token from its `room_ready`; a private room needs no code then. The guest gets `room_ready { rejoined: true }` with the same token, the host gets `room_ready { host: true, rejoined: true }`. If the guest is not back in time, the room closes: `room_closed { reason: 'opponent_timed_out', post_match: false }`. Quick match rooms and the host leaving still close the room as before.

## Session tokens

A token is 32 lowercase hex characters. It belongs to one seat in one room and stays the same across rematches in that room.

| Message | Dir | New fields |
|---|---|---|
| `room_created` | S -> C | `playerId: 0`, `token` |
| `room_ready` | S -> C | `playerId`, `token` (host still gets `host: true`) |
| `match_session` | S -> C | `code`, `playerId`, `token`, `holdSeconds` |

`match_session` is new. It is sent to both players right after `match_start` and again after a rematch starts. Store `{code, token}` when you get it and delete it when the match ends or the room closes.

## When a player drops mid-match

"Mid-match" means the server phase is `playing` or `pvp_pending`. A drop is any of: the socket closes, the player sends `return_to_menu`, or the player sends `leave_lobby`.

The server then:

1. Detaches that player's socket from the room and keeps the match.
2. Clears that player's Ready flag for the blind. If it was set, the other player gets `opponent_unready_blind`.
3. Pauses the PvP timer if one was running and sends `pvp_timer_paused` to the other player.
4. Sends the other player:

```
opponent_disconnected { held: true, reason, playerId, secondsLeft, holdSeconds }
```

`reason` is `connection_lost` (socket closed) or `left_to_menu` (`return_to_menu` / `leave_lobby`). `secondsLeft` is the time left before the match ends; count it down locally.

While a player is away, the other one can keep playing their own run. A PvP blind cannot start (both Ready flags are needed) and a PvP blind in progress cannot time out. If both players had already finished the PvP blind, it still resolves normally, and the returning player sees the result in `rejoin_ok`.

When both players are Ready, `start_blind { first }` goes to the room, where `first` is the player id of the one who was Ready first (Photo Finish reads it, so a replay gets the same answer as the live game). The late `start_blind` below has no `first`.

A `ready_blind` that arrives after `start_blind` went out for the current PvP blind (for example a player who dropped right as both were ready and sends Ready again after the rejoin) does not set a Ready flag or start the ante timer: the server answers that player with `start_blind` if they have not finished the blind yet. An `unready_blind` sent less than 0.9 s after that player's `ready_blind` (as the server sees it) is ignored and answered with `ready_blind_kept`, so the client shows Ready again instead of thinking it is unready.

`match_state_update` now also has `oppConnected` (bool) and `oppSecondsLeft` (number or null).

Old clients still treat `opponent_disconnected` as an instant win. New clients must check `held`: when it is `true`, show the Wait / Leave choice instead.

### The other player chooses Leave

```
C -> S  leave_match {}
```

If the opponent is away, the match ends with the leaver as the winner and the room closes. The reasons tell the whole chain: the player who left first gets `left_opponent_stopped_waiting` (or `dropped_opponent_stopped_waiting` when its connection was lost), the one who stopped waiting gets `stopped_waiting_opponent_left` (or `stopped_waiting_opponent_dropped`). If the opponent is still connected, it is a forfeit: the leaver loses (`forfeited`) and the opponent wins (`opponent_forfeited`), then gets `room_closed { reason: 'opponent_left' }`.

Either way the leaver gets its own `match_ended`.

`leave_match` outside a match (lobby or results screen) is the same as `leave_lobby`.

### The hold runs out

After 15 minutes the match ends. The player who stayed wins:

```
match_ended { reason: 'opponent_timed_out', result: 'win', ... }
room_closed { reason: 'opponent_timed_out', post_match: true }
```

The player who never came back sees `rejoin_expired` when they check.

## Coming back

### From the menu: is there a match to rejoin?

```
C -> S  check_rejoin { code, token }
S -> C  rejoin_status { code, rejoinable, matchOver, reason, opponentWaiting, opponentName?, secondsLeft?, mode?, ante?, result? }
```

- Rejoinable: `rejoinable: true`, `matchOver: false`, `reason: null`, `opponentWaiting` says if the other player is still connected, `secondsLeft` is the time left.
- Over: `rejoinable: false`, `matchOver: true`, `reason` says why (see the reason table), `result` is `win`, `lose` or `draw` from your side when known.
- Unknown: `reason: 'not_found'` (no room and no record) or `bad_token` (room exists, token does not match).

The server keeps the result of finished sessions for 1 hour so a player who comes back late still learns what happened.

### Rejoin

```
C -> S  rejoin_match { code, token }
S -> C  rejoin_ok { ... }        on success
S -> C  rejoin_failed { ... }    same fields as rejoin_status, plus reason 'already_in_room'
```

The socket must not be in another room. If the seat still has an old open socket (a half-dead phone connection), that socket gets `session_replaced` and is closed with code 4000.

`rejoin_ok` holds everything needed to restore the match:

| Field | Meaning |
|---|---|
| `code`, `playerId`, `host`, `token` | Your seat |
| `settings` | Room settings, same shape as `match_settings` |
| `seed` | Your seed (in vanilla mode P2 gets its own) |
| `phase`, `mode`, `startingLives`, `pvpStartAnte` | Match setup and server phase |
| `currentAnte`, `currentBlind`, `isPvpBlind` | Where the match is |
| `anteTimer`, `anteTimerBase` | Ante timer settings |
| `me` | `{ name, lives, status, location }` |
| `opp` | `{ name, lives, status, location, connected, secondsLeft }` |
| `pvp` | `{ pending, started, paused, timerMs, myReady, oppReady, myFinished, oppFinished, myScore, oppScore, lastResult }` |
| `pvpResults` | Every PvP result of this match |
| `gameHistory` | Earlier games in this room |
| `snapshot` | Your last uploaded save, `{ data, bytes, ante, blind, seq, at }`, or null |

`pvp.started` is true when `start_blind` was sent for the current PvP blind. `pvp.lastResult` is the last PvP result, so a player who missed a `pvp_resolved` can show it.

After `rejoin_ok`:

- The other player gets `opponent_reconnected { playerId }`.
- If the PvP timer was paused, both get `pvp_timer_resumed { ms }`. The timer restarts at full length so nobody loses a blind to time spent away.
- Both get a `match_state_update` with `event: 'player_rejoined'`.

Send `set_location` again after restoring so the other player sees where you are. The server now remembers the last location of each player for `rejoin_ok`.

### Giving up from the menu

A dropped player who does not want to come back:

```
C -> S  leave_match { code, token }
S -> C  rejoin_status { matchOver: true, reason: 'abandoned', result: 'lose' }
```

The other player gets `match_ended { reason: 'opponent_abandoned', result: 'win' }` and `room_closed { reason: 'opponent_abandoned' }`.

## Save snapshots

```
C -> S  save_snapshot { data, seq?, ante?, blind? }
S -> C  snapshot_ack { seq, bytes, stale }
```

- `data` is the save (Balatro's compressed `save.jkr` bytes) as standard base64. Decoded size must be at most 512 KB. Longer or non-base64 data gets `error { reason: 'save_snapshot: ...' }`.
- `seq` is an optional counter. A snapshot with a lower `seq` than the stored one is ignored and acked with `stale: true`.
- Only accepted during a match. The server keeps one snapshot per player, clears them when a new match starts, and returns yours in `rejoin_ok`.
- The frame limit is 1 MB for this message (4 KB for everything else). The usual `{"z":1,"d":...}` compression wrapper works.

Upload after each hand and on entering the shop or blind select. There is no need to upload more often than Balatro saves.

## How a match ends

Every match end sends each connected player:

```
match_ended { event, playerId, result, reason, winner, myLives, oppLives }
```

`result` is `win`, `lose` or `draw` for the receiver, and `reason` is from the receiver's point of view. A `match_state_update` with `phase: 'finished'` follows, and its `winReason` is now also per player. `pvp_resolved` still carries `matchEnded`, and its `winReason` is per player too.

| Cause | Winner gets | Loser gets |
|---|---|---|
| Last life lost (PvP or not) | `opponent_eliminated` | `eliminated` |
| Ascension | `ascension_farthest`, `ascension_score_tiebreak` or `ascension_draw` (both) | same |
| Client `match_finished` | the sent `reason` | its mirror (`opponent_eliminated` / `eliminated`, `opponent_forfeited` / `forfeited`, `opponent_quit` / `quit`, `opponent_disconnected` / `disconnected`), else the same reason |
| `leave_match` with the opponent connected | `opponent_forfeited` | `forfeited` |
| `leave_match` while the opponent is away (left to the menu) | `stopped_waiting_opponent_left` (the leaver) | `left_opponent_stopped_waiting` |
| `leave_match` while the opponent is away (connection lost) | `stopped_waiting_opponent_dropped` (the leaver) | `dropped_opponent_stopped_waiting` |
| Hold ran out | `opponent_timed_out` | `rejoin_expired` |
| Dropped player gave up | `opponent_abandoned` | `abandoned` |
| Room expired during a match | `room_expired` (both, draw) | |
| Last life lost in a sudden death round | `sudden_death_won` | `sudden_death_lost` |
| Vanilla mode `match_finished { result: 'win', reason: 'run_completed' }` | `run_completed` | `opponent_completed` |

If a match ends while one player is away (for example the other player loses their last life), the away player's result is stored for `check_rejoin` and the room closes with `opponent_disconnected`.

### The last PvP blind and sudden death

Only lives end a match (Nemesis and every PvP mode). The final ante is `settings.win_ante` when it is a whole number from 1 to 999 (the host picks it in the lobby: Auto or 3 to 16), else 10, 11, 12 or 13 for `stake` 9 to 12, else 8. The last PvP blind is the boss blind (`L`) of the final ante or later. It resolves like any PvP blind (the loser loses a life, a draw costs nothing), then:

- A player at 0 lives is eliminated and the match ends (`eliminated` / `opponent_eliminated`, or `sudden_death_won` / `sudden_death_lost` when it happens in a sudden death round).
- Otherwise the match goes on in sudden death: `suddenDeath` goes up by one, clients skip the Small and Big blinds of the next ante and play only its Nemesis blind, and so on until someone runs out of lives. Winning the last Nemesis blind no longer ends the match by itself, and neither does having more lives after a draw.

Fields: `pvp_resolved` has `finalPvp` (bool), `finalAnte` and `suddenDeath` (0 when none or when the match ended). `match_state_update` and `rejoin_ok` have `finalAnte` and `suddenDeath`. The reasons `final_nemesis_won`, `final_nemesis_lost`, `final_draw_more_lives` and `final_draw_fewer_lives` are no longer sent.

In PvP modes (any mode where the final ante's boss is PvP) the server ignores `match_finished { result: 'win', reason: 'run_completed' }`; lives decide. In vanilla and ascension the claim still ends the match.

### End-of-match viewer

```
C -> S  end_game_data { jokers: [{ k, ed?, st? }], deck?: { back?, cards: [{ f, e?, ed?, s? }] } }
C -> S  get_end_game_jokers {}
S -> C  end_game_jokers { playerId, available, jokers }
S -> C  nemesis_deck_data { playerId, available, back, cards }
```

- Send `end_game_data` once the match is finished. `k` is the joker key, `ed` the edition (`foil`, `holo`, `polychrome`, `negative`), `st` the stickers (`eternal`, `perishable`, `rental`). `f` is the card key (`H_A`), `e` the enhancement key (`m_glass`, left out for a base card), `s` the seal. Every key is 1 to 64 characters of `A-Z a-z 0-9 _ . : -`.
- Limits: 100 jokers, 8 stickers per joker, 1000 cards, 64 KB after the compression wrapper is unpacked. Anything else gets `error { reason: 'end_game_data: ...' }`. Outside a finished match: `end_game_data: no finished match`.
- The server keeps one copy per player and pushes it to the opponent right away (`end_game_jokers`, then `nemesis_deck_data`).
- `get_end_game_jokers` answers with the opponent's copy, or `end_game_jokers { available: false, jokers: [] }` when there is none yet.
- A new match (start or rematch) clears both copies. Seat swaps move them with their players.

## How a room closes

Every room close sends each player still in it:

```
room_closed { reason, post_match }
```

`post_match` is true when the match had finished (results screen). The old messages are still sent first for old clients, now with a `reason` field.

| What happened | Old message also sent | `room_closed.reason` |
|---|---|---|
| Opponent `leave_lobby` / `leave_match` in the lobby or results (in a lobby only when the host leaves; a guest leaving sends `guest_left`) | `opponent_left { post_match, reason }` | `opponent_left` |
| Opponent `return_to_menu` in the lobby or results | `opponent_returned_to_menu { post_match, reason }` | `opponent_left` |
| Opponent socket closed in the lobby | `opponent_disconnected { held: false, reason }` | `opponent_disconnected` |
| Opponent socket closed on the results screen | `opponent_left { post_match: true, reason }` | `opponent_disconnected` |
| Opponent forfeited or left while you were away | none | `opponent_left` |
| Hold ran out | none | `opponent_timed_out` |
| Dropped opponent gave up | none | `opponent_abandoned` |
| Room idle for 30 minutes | `room_expired { reason: 'ttl_expired' }` | `room_expired` |

`room_expired` is now really sent before the room is removed.

## Results screen

### Rematch votes

```
C -> S  rematch_vote {}
S -> C  rematch_status { votes: [p0, p1], by }     to both
S -> C  rematch_vote {}                            to the other player (old message)
```

Use `votes` and your own `playerId` to show "P1 wants a rematch" or "Waiting for P2...". When both have voted, both get `rematch_accepted` (as before), a `match_state_update` with `event: 'rematch_started'`, and a new `match_session`. A vote outside the results screen, or while one player is gone, gets `error { reason: 'rematch_unavailable' }`.

### Return to lobby (host only)

```
C -> S  return_to_lobby {}                 host only
S -> C  lobby_returned { by, rematchCleared, settings, gameHistory, code, host, playerId, token }   to both
S -> C  opponent_returned_to_lobby { gameHistory, code, host, playerId, token }   to the guest (old message)
```

The guest sending `return_to_lobby` on the results screen gets `error { reason: 'host_only' }`. If the room is already back in the lobby it is ignored, so old guests that echo it are harmless. The host sending it mid-match gets `error { reason: 'match_in_progress' }`. Rematch votes are cleared; `rematchCleared` is true when someone had voted.

In a room made with `create_room` (public or private) the room owner always stays host, so the room keeps its name ("<owner>'s room"), its code and its place in Browse, and the owner keeps the settings they picked. In a quick match the loser of the finished match hosts the next lobby: when seat 0 won, the server swaps both seats (sockets, tokens, names, game history) before it answers. `host`, `playerId` and `token` are each player's seat after that swap; tokens move with their player, so a stored session stays valid. A draw keeps the seats.

### Quit

On the results screen, `return_to_menu`, `leave_lobby` and `leave_match` all close the room. The other player gets the old message and `room_closed { reason: 'opponent_left', post_match: true }`. A socket closing on the results screen counts as a quit too (`reason: 'opponent_disconnected'`). Any rematch vote is dropped with the room.

## Match rules the server enforces

### Lobby settings

`match_settings { settings }` and `match_start { settings }` go through `sanitizeSettings` before they are stored in the room and forwarded to the other player (the guest gets the cleaned copy, not the raw message):

- Booleans (`different_seeds`, `different_decks`, `life_steal`, `timer`, `the_order`, `balance_enabled`, `multiplayer_jokers`, `allow_*`, `per_player_jokers`, the life rules) are dropped when they are not booleans.
- Whole numbers are clamped: `pvp_start_round` and `showdown_starting_antes` 1-39, `stake` 1-20, `pvp_win_money` 0-25, `timer_forgiveness` 0-10, `pvp_countdown_seconds` 0-10. `starting_lives` must be 1-20 and `win_ante` `false` or 1-999, or they are dropped.
- `timer_base_seconds` 0.2-3600, `timer_increment_seconds` 0-600. `custom_seed` at most 16 characters, `deck` at most 40.
- `rules` is the run rules diff (`RunRules.diff`, see docs/RUN_RULES.md): at most 120 keys of `[a-z0-9_]`, each a boolean, a number, a string up to 64 characters or a list of up to 300 such strings. Anything else is dropped. Both clients apply it with `RunRules.arm` before the run starts.
- `life_steal: true`: the winner of a PvP blind gets one life back, never above `starting_lives`, unless the loser was eliminated.
- `pvp_win_money` is paid by the winner's client when `pvp_resolved` says `win`.


### Seeds

The host sends `match_start { seed, settings }`. The server decides the real seeds:

- `custom_seed` (cleaned to A-Z and 0-9, at most 8, not `random`) wins when seeds are the same. If it differs from what the host sent, the host gets `match_seed { seed }`.
- `different_seeds: true` (or `same_seed: false`): the guest gets its own random 8 character seed in its copy of `match_start`. The custom seed is ignored.
- Rematches (`rematch_accepted { seed }`, one per player) and `rejoin_ok.seed` follow the same rule.

### Decks

```
C -> S  player_deck { deck }
S -> C  opponent_deck { deck }
```

The server keeps each player's pick and returns it as `rejoin_ok.myDeck`.

### PvP ready timer

On when `timer` (or the old `ante_timer`) is true. When one player sends `ready_blind` and the other is not ready, the other gets `timer_base_seconds` (or `ante_timer_base`) + `timer_increment_seconds` x (ante - 1) seconds.

```
S -> C  ante_timer { state: running|paused|stopped|expired, target: me|opp, msLeft, forgivenessLeft, lives, forgiven? }
```

- `stopped`: the timed player readied, the ready player un-readied or dropped, or the blind started.
- `expired` with `forgiven: true`: one of `timer_forgiveness` used, the countdown restarts.
- `expired` with `forgiven: false`: the timed player loses a life (`match_state_update { event: 'ante_timer' }`), the countdown restarts. At 0 lives the match ends with `eliminated` / `opponent_eliminated`.
- The clock pauses while either player is away and resumes on rejoin; `rejoin_ok.anteClock { target, msLeft, paused }` carries it.

## Error reasons added

`create_room: invalid visibility|name`, `join_room: invalid id|name|token`, `find_match: invalid name`, `<type>: invalid mods|version`, `ping: invalid rtt`, `host_only`, `match_in_progress`, `rematch_unavailable`, `save_snapshot: ...` (missing data, too large, data must be base64, invalid seq/ante/blind, no match in progress), `check_rejoin: invalid code|token`, `rejoin_match: invalid code|token`, `leave_match: invalid code|token`, `match_finished: invalid reason`, `player_deck: invalid deck`, `end_game_data: ...` (bad list, too many jokers or cards, invalid joker, card or deck, no finished match).

## Party rooms (protocol version 9)

Party rooms are a separate room type for 2 to 8 players with three modes: Battle Royale (`br`), Teams (`teams`) and Co-op Raid (`raid`). 1v1 rooms are unchanged. A party match reuses the 1v1 in-match messages, so the client's run flow (PvP blind wait, ready, life loss, elimination, results) works as is; party-only data comes in `party_state`. Every server message that belongs to a party carries `party: true`.

`MP_PROTOCOL_VERSION` is 9 and `OVERHAUL_VERSION` 2.3.

### Settings

Party settings are flat keys in the normal `settings` object, next to the 1v1 keys (lives, PvP start ante, stake, seed, deck, RunRules `rules`, life rules all apply). The server forces `mode: 'attrition'` (boss blind is PvP from `pvp_start_round`). Out of range numbers are clamped, wrong types dropped.

| Key | Type | Range | Default | Used by |
|---|---|---|---|---|
| `party_kind` | `'br' \| 'teams' \| 'raid'` | | `'br'` | all |
| `starting_lives` | int | 1-20 | 4 | br (per player), teams (per team) |
| `pvp_start_round` | int | 1-39 | 2 | all |
| `party_blind_seconds` | int | 60-600 | 180 | all: ready time limit after a PvP blind opens (then it starts for everyone inside it), and PvP blind time limit after `start_blind`, reset on every hand |
| `br_losers` | int | 1-3 | 1 | br: how many lowest scores lose a life per blind (always at most alive - 1) |
| `br_ties` | `'all' \| 'spare'` | | `'all'` | br: `all` = everyone tied at the cut loses, `spare` = players tied with the first safe score are spared |
| `br_sudden_death` | bool | | false | br: when two players remain, both drop to 1 life |
| `team_size` | int | 2-4 | 2 | teams: team count = ceil(players / team_size), at least 2 |
| `team_share` | int (percent) | 0-100 | 100 | teams: team score = best member + team_share% of every other member (100 = plain sum) |
| `team_auto` | bool | | true | teams: auto-balance teams at start (host assignment is ignored) |
| `raid_per_player` | int (percent) | 25-400 | 100 | raid: target share per player |
| `raid_scaling` | int (percent) | 0-100 | 0 | raid: extra target per ante above 1 |
| `raid_lives` | int | 1-20 | 3 | raid: shared lives |

Raid target = round(boss(ante) x players x raid_per_player/100 x (1 + raid_scaling/100 x (ante - 1))), where boss(ante) is 2x the base chips 300, 800, 2000, 5000, 11000, 20000, 35000, 50000 for antes 1-8 and 100000 x 1.6^(ante-8) after. `players` is the number of players still in the raid.

### Lobby, client to server

```
party_create  { kind?: 'br'|'teams'|'raid', visibility?: 'public'|'private', name, pkey?, mods?, version? }
party_join    { code? | id?, token?, name, pkey?, mods?, version? }   id (12 hex) from Browse; private rooms need code too; token = held seat
party_leave   {}                                   in lobby: seat is freed; a leaving host passes host to the next connected seat (closes only if nobody else is connected)
party_ready   { ready: bool }
party_team    { pid: 0-7, team: 0-3 }              host only, clamped to the team count
party_balance {}                                   host only, round-robin auto-balance
party_start   { seed? }                            host only; needs 2+ connected players and every guest ready
match_settings { settings }                        host only, lobby only (same message as 1v1)
player_name   { name, pkey? }
list_rooms    (as 1v1)                             party rooms are mixed into room_list
```

Name rules are the same as 1v1 rooms (default names refused, unique names, `pkey` keeps your own name). Version and mod set must match the host's, with the same `room_error`-style reasons sent as `party_error`.

### Lobby, server to client

```
party_joined { code, id, visibility, playerId, host, token, settings, version, rejoined? }   to the joiner (and creator)
party_room   { code, id, visibility, hostId, phase: 'lobby'|'playing'|'finished', maxPlayers: 8, kind, teams,
               players: [{ pid, name, ready, team, connected, held, secondsLeft }] }        to everyone on every change
party_error  { reason, id?, hostVersion?, yourVersion?, hostModded?, hostMods?, yourMods? }
             reasons: already_in_room, room_gone, invalid_code, code_required, in_match, room_full,
                      version_mismatch, mods_mismatch, not_enough_players, not_ready, need_two_teams
match_settings { settings }                        to guests when the host changes settings
room_closed  { reason, post_match, party: true }   host_left, room_expired, opponent_left
```

Seat ids (`pid`) are 0-7 and stable for the life of the party; the host is `hostId` (the creator; it moves to the next connected seat when the host leaves or drops, in the lobby too, so clients must watch `hostId`). A player that drops in the lobby keeps the seat for the hold time (15 min) and comes back with `party_join { code, token }`.

`room_list` entries for parties: `{ id, name (host), players, maxPlayers: 8, private, modded, mods, sameMods, inMatch, full, joinable, version, sameVersion, ping, mode: 'party_br'|'party_teams'|'party_raid', party: true, kind, seatHeld }`. Join them with `party_join { id, code? }`. `seatHeld` is true while a seat is on hold (in a match: a player who dropped or went to the menu and can still rejoin), for 1v1 rooms in a match too; the client shows REJOIN on the room whose `id` matches its stored `match_session.id`.

### Match start

On `party_start` every player gets, in this order:

```
match_start        { seed, settings, player_name (host), party: true, playerId }   start the run like a 1v1 guest
match_session      { code, id, playerId, token, holdSeconds, party: true }         keep for rejoin
match_state_update { ... see below }
party_state        { ... see below }
```

With `different_seeds` every guest gets a different random seed.

### In the match, client to server (same as 1v1)

`blind_entered { ante, blind }`, `play_hand { score, hands_left }`, `blind_finished { score, ante, blind }`, `game_over`, `ready_blind`, `unready_blind`, `set_location`, `save_snapshot`, `request_state`, `return_to_menu` / `leave_lobby` (drop, seat held 15 min), `leave_match` (forfeit: you are out, the party goes on), `return_to_lobby` (host, after the match).

### In the match, server to client

`match_state_update` per player: `{ party: true, event, phase, playerId, currentAnte, currentBlind, isPvpBlind, myLives, myStatus, oppName, oppLives, oppStatus, oppBlindFinished, oppConnected, oppSecondsLeft, winner, winReason, finalAnte, suddenDeath }`. `phase` is `finished` for a player who is out. The "opponent" is an aggregate:

| Mode | myLives | oppName | oppLives | opp score (enemy_info, pvp_resolved.oppScore) |
|---|---|---|---|---|
| br | own lives | rival name or `N rivals` | rivals alive | best rival score |
| teams | own team lives | `Team B` (best enemy team) | that team's lives | that team's score |
| raid | shared raid lives | `Raid Boss` | raid lives | raid target |

PvP blind flow: the first player to enter the PvP boss of an ante opens it for everyone. `opponent_ready_blind` / `opponent_unready_blind` tell you whether all other alive connected players are ready; `start_blind { party: true }` goes out when all alive connected players are ready. Live progress: every `play_hand` / `blind_finished` sends the others `enemy_info { score, hands_left: 0, lives, party: true }` (aggregate above) and everyone a fresh `party_state`.

Only one PvP blind is open at a time. A player who enters the next PvP boss while one is open waits; when it resolves, the next one opens if someone already waits at the next PvP blind of the schedule (a player further ahead never moves it to their ante). A player who readies on or enters a PvP blind that is already resolved, or that comes before the open one, gets a solo pass at once: `start_blind { party: true, solo: true }`, then `pvp_resolved { party: true, solo: true, result: 'draw' }` when they finish it (last `play_hand`, `blind_finished` or `game_over`), no lives change. A player who readies on or enters a PvP blind that already started gets `start_blind` right away. A player who is past the open PvP blind does not hold it: it starts without them and they count as 0. Scores sent for a PvP blind before it started are ignored. If not everyone is ready within `party_blind_seconds`, the blind starts for everyone already inside it.

`rejoin_ok` for a party carries the same settings as `match_start`, with `mode` `nemesis` (boss PvP blinds), `faceoff` (every blind) or `race`, so a restored run gets its PvP bosses back.

The blind resolves when every alive connected player has finished (or `party_blind_seconds` runs out; a connected player who never got there counts as 0). Nothing resolves while every alive player is disconnected. Absent players (disconnected and not finished themselves) use their one free drop per match and sit the blind out: not ranked in br, filled with the team average in teams. After the free drop they count with the score they had. In raid an absent player's partial score counts but their share is taken off the target. Rules:

- **br**: the `br_losers` lowest scores lose a life (ties per `br_ties`; all equal = draw; if `all` tie handling would hit everyone, only scores below the cut lose). 0 lives = out; players out in the same blind share the better placement. Last one standing wins.
- **teams**: lowest team score loses a team life (all equal = draw, tied lowest teams all lose). Short teams (forfeits, absent members, uneven split) are filled with their own members' average up to the biggest roster. A team at 0 lives is out with all members. Last team standing wins.
- **raid**: sum of all scores vs the raid target; below target = shared lives -1 for everyone. 0 raid lives = everyone loses. Clearing the PvP boss of the final ante wins for everyone; failing it with lives left costs a life and the next PvP boss is the final one again.

After the final ante, br and teams go on in sudden death (`suddenDeath` +1 per round) as in 1v1. Failing a normal blind with "Failed blind costs a life" on costs your pool (own lives, team lives or raid lives); with it off you get `match_state_update { event: 'round_lost' }` and keep your lives. A second `game_over` with the same `ante` and `blind` costs nothing more (answered with `round_lost`), as in 1v1.

```
pvp_resolved { party: true, result: 'win'|'lose'|'draw', myScore, oppScore, myLives, oppLives, matchEnded, winner (your pid or null),
               winReason, finalPvp, finalAnte, suddenDeath, lowest (pid), highest (pid), raidTotal, raidTarget }
match_ended  { party: true, event, playerId, result, reason, winner, myLives, oppLives, placement }
```

`matchEnded` is true for a player who is out or when the match is over. New end reasons: `last_standing`, `team_won`, `team_eliminated`, `raid_cleared`, `raid_failed`; plus `eliminated`, `forfeited`, `rejoin_expired`. `placement` is 1 for winners, else the finishing place.

`party_state` (to everyone, after every change):

```
{ type: 'party_state', kind, myId, phase, pvpAnte (open PvP ante or null), started,
  players: [{ pid, name, team, lives, alive, connected, score (this PvP blind or null), finished, placement }],
  teams:   [{ team, lives, alive, score }]          teams only
  lowest:  { pid, name, score } | null              live lowest / highest among scores this blind
  highest: { pid, name, score } | null
  raid:    { total, target, lives } | null }        raid only
```

Eliminated players keep receiving `party_state` until they leave, so they can watch the standings.

### Rejoin and after the match

Going to the menu mid-match (`return_to_menu`) holds the seat exactly like a dropped socket: the match goes on, missed blinds count as for a dropped player, and the others get `party_notice { event: 'menu' }` (a dropped socket sends `dropped`), then `rejoined` when the player is back. `leave_match { code, token }` from the menu gives the held seat up: the player is out (`abandoned`), the others get `party_notice { event: 'left' }`, and the sender gets `rejoin_status { rejoinable: false, reason: 'abandoned' }`. `check_rejoin` / `rejoin_match { code, token }` work for party codes. `rejoin_ok` has the 1v1 shape (with `party: true`, the aggregate `opp`, own `snapshot`), followed by `match_state_update { event: 'rejoined' }` and `party_state`. A player whose hold runs out is out (`rejoin_expired`). After the match the host sends `return_to_lobby`: seats that are not connected are dropped and everyone still connected gets `lobby_returned { party: true, settings, code, host, playerId, token, gameHistory: [] }` and a `party_room`.

Every odd case and the rule for it: `docs/PARTY_EDGE_CASES.md`.

### One join path and list fields

`join_room { code | id | token }` works for every room type: when the code or id belongs to a party, the server handles it as `party_join` and answers with `party_joined` or `party_error`, so the client never needs to know the type beforehand. Browse REJOIN and held-seat tokens use the same message.

`list_rooms` entries carry `lives` (starting lives from the room settings) and `ante` (the highest ante any player has reached, null in the lobby) for 1v1 rooms and parties alike, next to the existing slots, mode, version and mods fields.

## Ranked (big pass, new messages)

Rank is not a separate queue: every finished 1v1 or party match updates rank points (RP) for each human player with a player key. The server computes everything from what it already knows; the client never sends points. Identity is the MP player key (`pkey`, 24 letters and digits) that the client already sends with every message that carries `name`. Ranked requests carry `pkey` themselves.

### Points

- 9 ranks with tiers III, II, I (100 RP a tier, 300 a rank): Stone, Steel, Gold, Lucky, Glass, Foil, Holographic, Polychrome, Negative. Legendary from 2700 RP, no tiers, numbered by leaderboard place.
- Placement: 1v1 and Teams win +24, loss -20. Battle Royale goes linearly from +24 (1st) to -20 (last). Co-op Raid cleared +18, failed -10. Draw 0.
- Bonuses: ante reached +1 per ante above 1 (max 8), score +1 per digit above 10 000 (max 5), win streak +2 per win in a row before this one (max 10).
- A loss is the placement points times 0.25 (Stone), 0.4, 0.55, 0.7, 0.85 (Glass), 1, 1.1 (Legendary), plus half the bonuses, never above 0. RP never goes below 0.
- Bot factor: 0.5 + 0.5 x (human share of your opponents). A match against bots only counts half. Teammates do not count; Raid counts everyone else.
- A match where nobody left ante 1 does not count (`counted: false, reason: 'short'`). Solo VS Computer never reaches the server and does not count.
- XP: 60 + 15 per ante above 1 (max +140) + 40 for a win, times the bot factor. Level n needs min(1500, 300 + 50 x (n - 1)) XP; each level gives one Ranked Pack.

### Seasons

One calendar month (UTC), id `YYYY-MM`. The first time a player is seen in a new season their RP drops by one rank (300, floor 0), the season peak restarts, and they get the peak reward of the old season: `s<season>_b_<rank>` (animated badge variant) and `s<season>_k_<rank>` (sleeve).

### Cosmetics

Items are `{ id, type, name, rarity, value, source }`, `type` one of `badge`, `title`, `back`, `cframe`, `jframe`, `flame`, `burst`, `celebration`. Reaching a rank for the first time unlocks `rt_<r>` (title), `rk_<r>` (sleeve, value = shader), `rc_<r>` (card frame, value = hex colour), `rj_<r>` (joker frame, value = hex colour), `rf_<r>` (flame colour), `rb_<r>` (badge). Rank items added later are granted on profile load to players who already reached that rank. A Ranked Pack holds 3 items rolled by rarity (common 60, uncommon 28, rare 10, legendary 2); a duplicate turns into XP (25, 50, 100, 250). Everything is cosmetic.

### Messages

```
S -> C  ranked_result { match, mode: '1v1'|'br'|'teams'|'raid', placement, players, result, counted, reason, lines: [{ k, v }], delta, botFactor,
                        before: { rp, rank, tier, floor, next }, after: { ... }, promoted, demoted,
                        xp: { gain, before, after, levelBefore, levelAfter, needBefore, need }, packs, totalPacks, streak, unlocks: [item], season, party? }
        sent right after match_ended (1v1) or when the party match is over. lines k: placement, ante, score, streak, bots (percent), floor (only when the RP floor at 0 or the no-gain-on-a-loss rule changed the total).
        The total is round((placement + ante + score + streak) x bots / 100) + floor, so the lines always add up to delta.

C -> S  ranked_profile { pkey, name? }
S -> C  ranked_profile { store: 'memory'|'d1', profile: { name, rp, rank, tier, floor, next, legendNo, peakRp, peakRank, bestRank, xp, level, xpNeed, packs, streak, matches, wins },
                         season: { id, name, endsAt, secondsLeft }, unlocks: [id], equipped: { slot: id }, catalog: [item], last: ranked_result | null }

C -> S  ranked_leaderboard { pkey }
S -> C  ranked_leaderboard { season, top: [{ pos, name, rp, rank, tier, me }], me: { pos, rp, name, rank, tier } }     top 50 of the season

C -> S  ranked_history { pkey }
S -> C  ranked_history { matches: [{ id, mode, at, placement, players, result, ante, score, delta, xp, bots }] }     last 20

C -> S  ranked_open_pack { pkey }
S -> C  ranked_pack { items: [item + { dupe, xp }], levelUps }   then a fresh ranked_profile

C -> S  ranked_equip { pkey, slot, item | null }
S -> C  ranked_equipped { equipped }

C -> S  ranked_recovery { pkey }
S -> C  ranked_recovery { code }        XXXX-XXXX-XXXX

C -> S  ranked_restore { code }         5 tries a minute per socket
S -> C  ranked_restored { pkey, name, rp, rank, tier }       the client adopts pkey as its player key

C -> S  ranked_badges { names: [string] }     up to 16 names
S -> C  ranked_badges { badges: { name: { r, t, n, title, badge } } }     only players the server knows; r rank, t tier, n Legendary number

C -> S  ranked_test_set { pkey, rp?, packs?, level?, xp? }     test only: the server accepts it only when MP_TEST_RANKED_RP is set
                                                     (never in production); replies with ranked_profile

S -> C  ranked_error { reason: 'no_key'|'offline'|'no_pack'|'bad_item'|'bad_code'|'slow_down', for }
```

### Storage

Cloudflare D1 over the HTTP query API. The server reads `CF_ACCOUNT_ID`, `CF_D1_DATABASE_ID` and `CF_API_TOKEN`; without them (tests, local) it keeps everything in memory behind the same interface. Profiles are cached in memory; writes go through an ordered queue that retries with backoff (2 s doubling to 2 min) when D1 fails, drops a write D1 refuses three times with a 4xx, and keeps at most 5000 writes. A match result for a player whose profile cannot be read is kept and applied when the profile loads. Schema: `server/migrations/0001_ranked.sql`.

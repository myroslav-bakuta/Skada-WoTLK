# Skada WotLK (mod by Kappa)

A maintenance fork of [Skada Revisited](https://github.com/bkader/Skada-WoTLK) by Kader (bkader), the modular damage meter for World of Warcraft 3.3.5a (WotLK, Interface 30300).

This fork exists for two reasons: to fix bugs that were still present in the upstream release, and to add a complete Ukrainian localization. Roughly thirty defects were found and fixed, ranging from a performance problem that froze the client for seconds at a time to several latent crashes and a number of incorrect calculations. All fixes are described in detail below.

Bug fixes, extensions and the Ukrainian translation by **Kappa**.

## Requirements

* World of Warcraft 3.3.5a client (Interface 30300)
* No other dependencies, all required libraries are bundled

## Installation

Copy the three folders into your `Interface\AddOns\` directory:

```
Interface\AddOns\Skada\
Interface\AddOns\SkadaImprovement\
Interface\AddOns\SkadaStorage\
```

Only `Skada` is enabled by default. `SkadaImprovement` and `SkadaStorage` ship with `DefaultState: disabled`, so enable them in the character selection AddOns list if you want them:

* **SkadaImprovement** records your own boss fight statistics over time so you can compare your performance across attempts.
* **SkadaStorage** keeps combat segments in saved variables so they survive a logout, and warns you when memory usage grows too large.

## Ukrainian localization

The addon is displayed in Ukrainian by default. The translation is complete: all 809 strings are covered, with English used as the fallback for anything a future version adds.

The 3.3.5a client has no `ukUA` game locale, so the usual AceLocale mechanism cannot be used for it. Instead the translations are stored separately and overlaid onto whichever locale the client is running, which means Ukrainian works correctly on an English or Russian client alike.

To switch back to the client language, open `/skada config`, go to the General tab and turn off the option under "Мова / Language". The setting is account wide and requires a UI reload, which the addon will prompt for.

Bundled languages are English, Russian and Ukrainian. The German, Spanish, French, Korean and Chinese translations that shipped upstream were removed. Players on those clients will see English as the base language, with the Ukrainian overlay applied on top unless they disable it.

## What is changed compared to the original

### Performance

* **Snake Trap and enemy pet freezes are fixed.** This was the most severe problem. When a combat log event arrived from a unit whose owner Skada could not identify, it ran a full raid roster scan followed by a tooltip scan that tested every actor in the segment against every summon pattern, with each test performing an expensive `SetText`/`GetText` round trip on a font string. Successful lookups were cached but failures were not, so an unresolvable unit repeated that entire scan on every single event it generated. A hunter's Snake Trap summons around six guardians that each attack quickly and apply poisons, and an enemy hunter's snakes can never be resolved at all because they are not in your group, which produced freezes lasting several seconds in PvP. Unresolvable GUIDs are now remembered for 30 seconds before being retried, and the cache is pruned periodically so it cannot grow without bound over a long session.

### Crashes

* **Tweaks:** clicking an outdated `SKSP` report link after the corresponding meter was removed raised a Lua error.
* **Threat:** the module errored when `Blizzard_CombatText` was not loaded.
* **Comparison:** three nil dereferences when the "absorbed damage" option was enabled.
* **Absorbs:** `UnitAttackPower` returns nil for players other than yourself, which broke the Savage Defense calculation.
* **Init:** `SpellLink` errored on spells passed by name, a latent crash reachable through the Interrupts and CCTracker announcements.
* **SunderCounter, Damage:** missing nil guards on actor and total lookups.
* **Core:** a typo in `verify_set` would have errored for any module defining `AddPlayerAttributes` or `AddEnemyAttributes`.

### Correctness

* **Windows:** an operator precedence mistake in `set_active` caused visible windows to be hidden when they should have stayed open.
* **SmartStop:** a broken condition chain made the option do nothing at all and inverted the creature ignore list.
* **Enemies:** `type(unit.diff == "table")` always evaluated to `"boolean"`, so instance difficulty was never matched correctly. The "Enemy Healing Done" window title also grew endlessly, repeating the class name on each refresh.
* **Deaths:** the death log entry was keyed by GUID on cleanup but by name on insertion, so it was never cleared after a resurrection and the death aura blocked the next record.
* **Healing:** a fully overhealed hit recorded a minimum of zero, skewing the minimum healing figure. This applies to both normal hits and criticals. Hit counts and totals still include those hits, only the minimum and maximum skip them.
* **Comparison:** blocked damage was labelled `RESIST` instead of `BLOCK`.
* **Parry:** announcements were duplicated once per boss phase because phase segments were also matched.
* **Nickname:** the broadcast timer was cancelled with a string instead of the timer handle, so it was never actually cancelled.
* **Absorbs:** the HPS tooltip used the wrong title template, and the "Healing Done By Spell" tooltip displayed fields that were never populated instead of the real minimum and maximum.
* **Enemies:** `GetDTPS` was called with three arguments on a two parameter method.

### Memory

* **Global leaks:** an undeclared local in `Init.lua` and a missing function parameter in `Healing.lua` both leaked into the global namespace.
* **Table pool leaks:** temporary tables were not returned to the pool in `Deaths.lua` and in the Avoidance and Mitigation view of `DamageTaken.lua`.
* **Shared state:** `setPrototype:Bind` wrote the arena flag onto the shared prototype rather than the individual segment, so the flag leaked between segments.

### Housekeeping

* Version raised to 1.9.0 and declared consistently in all three addons. The two plugins previously had no version field at all.
* `X-Curse-Project-ID` removed, since this fork is not connected to the upstream Curse project.

## Not audited

The work above concentrated on the core and the feature modules. The following were not reviewed in depth and may still contain issues: `Core/Display/*` (Bar, Inline, Broker, Legacy), `Options.lua`, `Menus.lua`, and the bundled third party libraries in `Libs/`.

One deliberate non change is worth recording: in `Modules/Resurrects.lua` the `SPELL_RESURRECT` registration uses the `src_is_not_interesting` flag, which looks suspicious but is plausibly intentional, since changing it blindly risks counting every resurrection twice.

## Credits

* **Zarnivoop**, author of the original Skada.
* **Kader (bkader)**, author of Skada Revisited, the fork this is based on.
* **Kappa**, bug fixes, extensions and Ukrainian localization.

Licensed under MIT/X, same as upstream.

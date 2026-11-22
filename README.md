# LeaveButton

A "get off at next stop" button on flight paths in **WoW Forever**, where Blizzard's own button
doesn't appear.

| On a flight path | After clicking |
|---|---|
| ![LeaveButton on a flight path with its tooltip](docs/taxi.png) | ![LeaveButton after a click: Landing at next stop](docs/requested.png) |

## What it does

- On a flight path, a button above your action bars lands you at the next flight master. After
  a click it reads "Landing at next stop" until you land.
- In a vehicle, the same button leaves it, but only when Blizzard's leave button isn't showing.
- It isn't a protected button, so it works in combat.
- Shift-drag it to move it; the position is saved for all your characters.

## Commands

| Command | |
|---|---|
| `/leavebutton` | What it does and the list of commands |
| `/leavebutton move` | Shows the button now so you can place it (Shift-drag), click it when done |
| `/leavebutton reset` | Back to the default position |

## Install

Download this repository (green **Code** button, **Download ZIP**), and copy the
`addons\LeaveButton` folder into `World of Warcraft\_forever_\Interface\AddOns`, so that you
end up with `AddOns\LeaveButton\LeaveButton.toc`. Restart WoW fully (a `/reload` doesn't
find new addons).

No other addons needed.

## Limits

- It checks for a flight start or landing every 2 seconds as well as on events, so the button
  can take a moment to appear or go.
- Mostly tested on flight paths; vehicles are rare in WoW Forever.

## Licence

[MIT](LICENSE)

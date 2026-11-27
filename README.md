# The Fishing Log (Test)

A test build of [The Fishing Log](https://www.curseforge.com/wow/addons/the-fishing-log)
for WoW: Forever, shared so the addon's author and invited testers can read the
changes, run them, and pull updates.

This is **not a release** and not a replacement for the addon on CurseForge.
The Fishing Log is by Jake; the built-in look is based on Godfall's UI Rework
(MIT, see `LICENSE-UIRework.txt`); bundled libraries keep their own licences
(`Libs/README.txt`). Everything that differs from the original is listed in
[`CHANGES.txt`](CHANGES.txt).

## What is different

- **Character panel** in the journal (build 1).
- **Record sync fixes**: whisper follow-ups, relaying records of offline
  holders, transfer time-outs (build 2).
- **Sync alerts and reports**, local only (build 3).
- **A network of its own** (build 4): this build only talks to other copies of
  this build. It uses its own addon-message prefixes (`FishingLogTest`,
  `TFLUIFaceTest`), its own finder channel (`TheFishingLogTest`) and its own
  save-macro names (`TFL Test 1..4`). Players on the original addon neither
  see nor receive anything from it. Message formats, the launch-date envelope
  and all shared tables are unchanged from 1.1.4.

The version line stays `1.1.4`. The build number is the `X-Build` line in the
toc; it shows in the journal title and in diagnostics and is never sent.

## Reading the changes

The history is one commit per step, on top of the untouched original:

| Commit | Contents |
|---|---|
| The Fishing Log 1.1.4 by Jake, unmodified | the base to compare against |
| Test build 1 .. 4 | one commit per build |
| Tests and README | mock-client tests, this file |

`git diff <base commit> HEAD -- . ':!tests' ':!README.md'` shows every change
to the addon in one diff.

## Installing

The game only loads an addon whose folder has the same name as its `.toc`, so
the folder must be called `TheFishingLogTest`.

- **With git:** in `World of Warcraft\_forever_\Interface\AddOns`, run
  `git clone <this repository's URL> TheFishingLogTest`. Update later with
  `git pull` inside that folder.
- **From a ZIP:** download, unpack, and rename the folder to
  `TheFishingLogTest` (GitHub adds the branch name to it).

Then:

1. Restart the game client (a `/reload` does not pick up a new addon).
2. In the AddOns list, tick **The Fishing Log (Test)** and untick the original
   **The Fishing Log**. With both ticked the test build stays switched off and
   says so at login.
3. The test build keeps its own saved data, filed under its folder name. It
   starts empty and does not touch the original's data. To start from your
   existing log, log out and copy `TheFishingLog.lua` to
   `TheFishingLogTest.lua` in `WTF\Account\<account>\SavedVariables` and in
   each character's `SavedVariables` folder.

You will only see other anglers who run this build.

## Tests

The tests load the real addon files against a small mock of the game client.
They need Node.js and no game.

```
cd tests/lua-parser && npm ci && cd ../..
node tests/check-fishing-lua.cjs
for t in sync sync-report sync-report-ui portrait isolation; do
  node tests/lua-parser/node_modules/fengari-node-cli/src/lua-cli.js tests/test-fishing-$t.lua
done
```

`tests/legacy-1.1.4/Records.lua` is the original 1.1.4 file, used as the
"unmodified client" in the sync tests.

Mock tests do not show rendering or real player-to-player delivery. As of
build 4, two clients finding each other in game has not been confirmed yet.

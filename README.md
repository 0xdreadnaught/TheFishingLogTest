# The Fishing Log (Test)

This is a test build of [The Fishing Log](https://www.curseforge.com/wow/addons/the-fishing-log) for WoW: Forever. It is not the main addon. If you just want to fish, install that one from CurseForge and ignore this.

I use The Fishing Log and wanted to try some changes to it. This is my working copy, put here so the author and anyone who feels like testing can read the code and pull updates. None of it is official and it can break.

It only talks to other copies of the test build, so your realm is going to look empty: no records, bounties, matches or events from anyone on the main addon. It also keeps its own saved data, so your real log isn't touched.

## What's changed

Based on 1.1.4. The full notes are in [CHANGES.txt](CHANGES.txt).

- A character panel on the left side of the journal that shows your fishing outfit.
- Record sync fixes. Whisper replies go back to whoever asked, record books pass along records held by people who are offline, and large transfers time out properly.
- A sync report that opens after a sync and shows what came in.
- Its own message prefix and channel, which is why it can't see the main addon.
- A chat message at login saying it's the test build.

## Install

The folder has to be named `TheFishingLogTest` or the game won't load it.

With git, from `World of Warcraft\_forever_\Interface\AddOns`:

```
git clone https://github.com/0xdreadnaught/TheFishingLogTest.git TheFishingLogTest
```

Run `git pull` in that folder to update. If you download the ZIP instead, rename the folder after unpacking, because GitHub adds `-main` to the name.

Restart the game. A `/reload` won't find a new addon. In the AddOns list turn on "The Fishing Log (Test)" and turn off the original. If both are on, the test build shuts itself off and tells you so at login.

The test build starts with an empty log. To bring yours over, log out, then copy `TheFishingLog.lua` to `TheFishingLogTest.lua` in `WTF\Account\YOURACCOUNT\SavedVariables`. Do the same in each character's `SavedVariables` folder.

## For the author

The first real commit is 1.1.4 untouched (`18e3680`), then one commit per build. This shows everything I changed:

```
git diff 18e3680 HEAD -- . ':!tests' ':!README.md'
```

The version line is still 1.1.4 on purpose. The build number is the `X-Build` line in the toc and it is never sent to other players.

The network split is four constants: `MF.PREFIX` and `MF.CHANNEL` in `Comm.lua`, `PREFIX` in `Rework/RealmPage.lua`, and `MACRO_NAME` in `Storage.lua`. Message formats are the same as 1.1.4.

## Tests

The tests run the real addon files against a fake game client. You need Node.

```
cd tests/lua-parser && npm ci && cd ../..
bash tests/run-all.sh
```

They can't tell you how anything looks or whether two real players sync. Nobody has confirmed two test builds finding each other in game yet.

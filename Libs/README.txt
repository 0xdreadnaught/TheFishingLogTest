Bundled mapping dependencies

LibStub: public domain; original author credits retained in source.
CallbackHandler-1.0: upstream standalone callback library, revision 8.
HereBeDragons-2.0: Nevcairiel, revision 35, BSD (upstream X-License metadata).
HereBeDragons-Pins-2.0: Nevcairiel, revision 17, BSD.
Upstream: https://github.com/Nevcairiel/HereBeDragons

These are general-purpose WoW libraries, not GatherMate2's collector,
database, display module, artwork or node definitions. The Fishing Log
does not depend on, read, import or alter GatherMate2.

The pin library includes a dependency guard; all remaining library code
is preserved. The simulation harness parses vendor Lua but injects map
library APIs for feature tests; minimap physics require in-game testing.

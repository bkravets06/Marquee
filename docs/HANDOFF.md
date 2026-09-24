# Handoff: continuing Marquee in a local session

This project was built in a cloud session that had no Xcode, no simulator and
no TMDB token. A local session on 2026-09-24 (Xcode 27, iOS 27 simulators,
live TMDB token) then ran the app and walked the checklist below; results are
under *Verification results*, including the checks done on a physical device.

## Where things stand

- `main` holds the complete app and is the default branch (renamed from
  `claude/ios-show-movie-tracker-ilhaq1`; GitHub redirects the old name).
- CI (`.github/workflows/ci.yml`, macOS 26 / Xcode 26.6 / iPhone 17 Pro
  simulator) is green: app build with zero warnings, 132 MarqueeKit tests,
  61 app tests. Runs: https://github.com/bkravets06/Marquee/actions
- CI also installs the Debug build in the simulator, launches it with the
  debug launch arguments below and captures screenshots. A push whose commit
  message contains `[screenshots]` commits them to `docs/screenshots/`
  (`git pull` before you push; if a CI push was rejected because the branch
  moved, just push another `[screenshots]` commit).
- `docs/ARCHITECTURE.md` is the contract between modules; `CLAUDE.md` has the
  conventions. Read both before changing structure.

## First: run it

1. Open `Marquee.xcodeproj`, pick an iPhone simulator, Run.
   Command-line equivalent:
   ```sh
   UDID=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(dev["udid"] for rt,devs in d["devices"].items() if "iOS" in rt for dev in devs if dev["name"].startswith("iPhone")))')
   xcodebuild -project Marquee.xcodeproj -scheme Marquee -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
   xcrun simctl bootstatus "$UDID" -b && open -a Simulator
   xcrun simctl install "$UDID" build/Build/Products/Debug-iphonesimulator/Marquee.app
   xcrun simctl launch "$UDID" com.bjkravets.marquee
   ```
2. Onboarding page 2 asks for a TMDB **API Read Access Token**
   (https://www.themoviedb.org/settings/api, free). The user pastes it there;
   it is stored in the Keychain. For repeated Debug launches you can instead
   set `TMDB_ACCESS_TOKEN` in the scheme's environment variables, or launch
   with `SIMCTL_CHILD_TMDB_ACCESS_TOKEN=<token> xcrun simctl launch ...`.
   Never write the token into a file, scheme shared data, or a commit.
3. Walk the flows: Discover carousels load → tap a show → detail → add to
   Watching → Library row shows progress → mark next episode watched → open
   Seasons → episode list → Search → quick add → custom title via Library `+`
   → Settings (key, reminder time, region, refresh, delete all) → toggle
   reminders on a show (permission prompt) → background it and return.

## Verify these specifically

Reviewers flagged these as correct-by-reading but only provable on a device:

- **Library segments.** `LibraryListView` rebuilds its `@Query` in `init`
  from the selected segment. If switching Watching/Watchlist/Watched shows
  stale rows, add `.id(selectedStatus)` to the outer `List` in
  `Marquee/Features/Library/LibraryView.swift` (not to `LibraryListView`).
- **Seasons push inside the Library tab.** `SeasonsView` uses a
  destination-based `NavigationLink` inside a stack bound to a typed path
  (`[LibraryRoute]`). Confirm the episode list pushes and pops cleanly.
- **Detail scroll.** `MediaDetailView` uses `.onScrollGeometryChange` to fade
  the navigation bar over the backdrop; check it looks right at the top and
  after scrolling, in light and dark mode.
- **Symbols.** Onboarding uses `sparkles.tv`; if it renders blank, use `tv`.
- **Search tab on iOS 26.** The tab uses `Tab(role: .search)`; confirm the
  system search presentation and the scope bar behave.
- **Prominent buttons.** Labels use `Color.onAccent` (black on the gold
  accent, see `Marquee/Support/Theme.swift`). Check the `ProgressView`
  spinners inside the Validate & Save buttons are visible while validating.
- **Notifications.** Toggle a show's reminders → permission prompt → Settings
  footer shows the pending count. Change the reminder time and confirm the
  count is unchanged (requests are replaced, not duplicated). A custom show
  with a weekly schedule should add one repeating request. Tap a delivered
  notification → the app opens that show (deep link via `Navigator`).
- **Background refresh.** With the app running under the debugger, pause and
  run
  `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.bjkravets.marquee.refresh"]`
  then resume; the console should show the refresh and reminders re-sync.
- **Dynamic Type, dark mode, iPad.** Largest accessibility sizes on Library
  rows, the detail progress card and the custom form; iPad landscape layout.
- **Empty and error states.** Remove the key in Settings and confirm Discover
  and Search show the connect state with a working button to Settings; turn
  Wi-Fi off and confirm inline retry rows appear.

Fix what you find with minimal, targeted changes; keep the conventions in
`CLAUDE.md`; run `swift test --package-path MarqueeKit` and the Xcode tests;
commit in small steps and push (CI is the shared source of truth).

## Verification results (local session, 2026-09-24)

Driven with XCUITest from a scratch project (not in the repo) on an iPhone 17
Pro and an iPad Pro 11-inch simulator, light and dark, default and largest
accessibility text size, with a live TMDB token.

Confirmed working as written:

- Library segments switch without stale rows; no `.id(selectedStatus)` needed.
- Seasons → episode list pushes and pops cleanly inside the Library stack,
  repeatedly.
- Detail navigation bar fades in over the backdrop on scroll, light and dark.
- `sparkles.tv` renders in onboarding.
- Search tab (`Tab(role: .search)`) presents natively; All/Shows/Movies scopes
  filter; no-results state offers "Add as Custom Title".
- Discover carousels and See All load; detail → Add to Library → Watching.
- Notifications: permission prompt on the reminders toggle; pending count 1;
  changing the reminder time keeps it at 1; a custom weekly show adds one
  (2). A notification carrying `itemID` (sent with `xcrun simctl push`) opens
  that show's detail when tapped.
- The spinner in onboarding's Validate & Save is visible while validating;
  a valid token saves and onboarding advances.
- Empty states for all three segments, the no-token connect state (Open
  Settings works) and the rejected-key error state with Retry.
- iPad landscape: top tab bar, readable-width detail, seasons, search.

Fixed in commit aa5656f (see its message): accent-tinted episode rows, the
collapsed Library empty-state button, a blank gap under Settings' TMDB status,
the wrapping Mark Next button, the Up Next blank line, and layouts at
accessibility text sizes.

Verified on a device (iPhone 16 Pro Max, iOS 27, Debug build, same day):

- **Background refresh.** With a refresh request submitted and
  `_simulateLaunchForTaskWithIdentifier` run from lldb, the handler runs on
  the `com.apple.BGTaskScheduler (com.bjkravets.marquee.refresh)` queue and
  reaches "Background refresh finished" after the library refresh. (The
  simulator cannot run BGTaskScheduler at all.)
- **A real reminder** for a custom weekly show fired at the set time, and
  tapping it cold-launched the app straight into that show.
- **Offline.** Refreshing Discover in Airplane Mode keeps the content already
  loaded; everything reloads once the network is back.

To run on a device from the command line (team ID stays out of the project):
`xcodebuild ... -destination "platform=iOS,id=<udid>" DEVELOPMENT_TEAM=<team> -allowProvisioningUpdates build`,
then `xcrun devicectl device install app` and
`DEVICECTL_CHILD_TMDB_ACCESS_TOKEN=... xcrun devicectl device process launch --device <udid> com.bjkravets.marquee -- <launch arguments>`
(note the `--` before the app's arguments). Attaching lldb to a device app
takes about a minute; if an lldb batch script stops on an error it kills the app.

Note: unsigned builds (`CODE_SIGNING_ALLOWED=NO`) cannot write to the
Keychain (`errSecMissingEntitlement`, -34018), so saving a key fails there.
Xcode's normal Run signs ad hoc and works.

## Debug launch arguments (Debug builds only)

| Argument | Effect |
| --- | --- |
| `-settings.hasCompletedOnboarding YES` | Skip onboarding (a real setting) |
| `-marquee.initialTab discover\|library\|search` | Select a tab on launch |
| `-marquee.seedLibrary YES` | Fill an empty library with six titles (via TMDB when a token exists, otherwise preview fixtures) |
| `-marquee.openSeededItem YES` | Push the first seeded show's detail screen |

`scripts/ci-screenshots.sh <udid> <path/to/Marquee.app> [out-dir]` drives a
booted simulator through these and writes PNGs; it is what CI runs.

## Screenshots

`docs/screenshots/` holds live-data captures (Discover, Library, Detail, light
and dark). CI has a `TMDB_ACCESS_TOKEN` secret, so its smoke run uses live
TMDB data too; put `[screenshots]` in a commit message (or run the workflow
manually with *commit_screenshots*) to refresh them.

## Known follow-ups (optional, in rough priority)

1. Roadmap items from the README: Up Next widgets, iCloud sync, Trakt import,
   watch providers.

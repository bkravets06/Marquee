# Handoff: continuing Marquee in a local session

This project was built in a cloud session that had no Xcode, no simulator and
no TMDB token. Everything compiles and tests green on CI, but **no human has
run the app yet**. The next session runs on a Mac with Xcode and should treat
"run it, verify it, polish what a real device reveals" as its job.

## Where things stand

- Branch `claude/ios-show-movie-tracker-ilhaq1` holds the complete app and is
  currently the repository's default branch (there is no `main` yet).
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

## Debug launch arguments (Debug builds only)

| Argument | Effect |
| --- | --- |
| `-settings.hasCompletedOnboarding YES` | Skip onboarding (a real setting) |
| `-marquee.initialTab discover\|library\|search` | Select a tab on launch |
| `-marquee.seedLibrary YES` | Fill an empty library with six titles (via TMDB when a token exists, otherwise preview fixtures) |
| `-marquee.openSeededItem YES` | Push the first seeded show's detail screen |

`scripts/ci-screenshots.sh <udid> <path/to/Marquee.app> [out-dir]` drives a
booted simulator through these and writes PNGs; it is what CI runs.

## Then: screenshots and README

Once the screens look right, capture Discover, Library and Detail (light and
dark), put them in `docs/screenshots/`, and replace the placeholder in the
README's *Screenshots* section (a commented-out table is already there).

## Known follow-ups (optional, in rough priority)

1. Rename the branch to `main` and make it the default on GitHub once the
   owner agrees (`git branch -m main && git push -u origin main`, then
   Settings → Branches).
2. Add a LICENSE (owner's choice) and a README *License* section.
3. `NotificationManager` has no `cancelAll()`; `SettingsView` talks to
   `UNUserNotificationCenter` directly for Delete All Data. Adding
   `cancelAll()` keeps the manager as the single entry point.
4. `BackdropHeader` fades into `systemBackground` while the detail page uses
   `systemGroupedBackground`; `MediaDetailView` overlays a second gradient.
   A `fadeColor` parameter on `BackdropHeader` would be cleaner.
5. Roadmap items from the README: Up Next widgets, iCloud sync, Trakt import,
   watch providers.

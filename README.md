# Watch Planner

Personal iPhone app that puts the structured runs from `schedule.json` in the Workout app on Apple Watch, using WorkoutKit's `WorkoutScheduler`.

With a free Apple ID the app expires after 7 days. Run the commands below to rebuild and reinstall. Your pasted schedule survives a reinstall; it lives in the app's Documents folder.

## Rebuild and reinstall

Xcode lives in `~/Downloads/Xcode.app` on this Mac, so point the tools at it:

```bash
export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
```

Generate the project (fill in your team ID, see below):

```bash
TEAM_ID=XXXXXXXXXX xcodegen generate
```

Build and sign:

```bash
xcodebuild -project WatchPlanner.xcodeproj -scheme WatchPlanner -destination generic/platform=iOS -derivedDataPath build -allowProvisioningUpdates build
```

Find your iPhone's identifier (phone connected and unlocked):

```bash
xcrun devicectl list devices
```

Install:

```bash
xcrun devicectl device install app --device <identifier> build/Build/Products/Debug-iphoneos/WatchPlanner.app
```

Your team ID is in Xcode > Settings > Accounts > your Apple ID > Personal Team, or in `security find-identity -v -p codesigning` (the code in brackets after "Apple Development").

## First install on the phone

1. Instellingen > Privacy en beveiliging > Ontwikkelaarsmodus aan (phone restarts).
2. After installing: Instellingen > Algemeen > VPN en apparaatbeheer > your Apple ID > Vertrouw.

## Schedule format

See `WatchPlanner/Resources/schedule.json`. Goal types: `time` (unit `sec` or `min`), `distance` (unit `km`), `open`. `zone` (1 to 5) is optional and adds a heart rate zone alert. An easy run is one block with one `work` step and `iterations: 1`.

To load a new schedule: copy the JSON, open the app, tap the clipboard button ("Plak nieuw schema"), then "Plan op Watch".

## Check that it worked

- On the Watch: open Workout, scroll to Hardlopen buiten, tap the `...` button. The planned workouts are listed there. The one for today also appears at the top of the Workout app.
- On the iPhone: the Fitness app shows the planned workouts in the Workout tab.
- In the app, workouts that landed show "Op Watch".

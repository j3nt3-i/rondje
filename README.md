# Rondje

Personal iPhone app that puts structured runs in the Workout app on Apple Watch, using WorkoutKit's `WorkoutScheduler`. Workouts are grouped in events (a race with its training schedule). The bundled `schedule.json` (Devil's Trail) is the first event.

With a free Apple ID the app expires after 7 days. Run the commands below to rebuild and reinstall. Your events survive a reinstall; they live in `events.json` in the app's Documents folder.

## Rebuild and reinstall

Xcode lives in `~/Downloads/Xcode.app` on this Mac, so point the tools at it:

```bash
export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
```

Connect and unlock the iPhone, then generate the project:

```bash
xcodegen generate
```

Build and sign (this also renews the 7-day profile):

```bash
xcodebuild -project WatchPlanner.xcodeproj -scheme WatchPlanner -destination id=00008150-00112C3A3693C01C -derivedDataPath build -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```

Install:

```bash
xcrun devicectl device install app --device 00008150-00112C3A3693C01C build/Build/Products/Debug-iphoneos/WatchPlanner.app
```

The team ID (`YZV5DX4L6Y`, Personal Team) is set in `project.yml`. `00008150-00112C3A3693C01C` is the iPhone 17 Pro; for another phone, find its identifier with `xcrun devicectl list devices`.

## First install on the phone

1. Instellingen > Privacy en beveiliging > Ontwikkelaarsmodus aan (phone restarts).
2. After installing: Instellingen > Algemeen > VPN en apparaatbeheer > your Apple ID > Vertrouw.

## Adding workouts

- **One workout**: open an event, tap `+`, pick a date and type the workout. A preview shows how it will look.
- **A whole program**: on the home screen tap `+` > "Kopieer prompt voor Claude", paste it in Claude with your goal, copy the answer, then `+` > "Importeer schema" and paste. An event with the same name is replaced. JSON in the old `schedule.json` format works too.
- **Edit with Claude**: in an event, `...` > "Kopieer als tekst" gives the whole schedule in the same format.

Text format:

```
Zevenheuvelenloop
tijd 07:00

2026-12-01 Di intervallen
warmup 10 min z2
5x 3 min z4 / 2 min z2
cooldown

2026-12-03 Do duurloop
10 km z2
```

- A line starting with a date (`2026-12-01` or `1-12-2026`) starts a workout; the rest of the line is its name (optional).
- `warmup <goal>`, `cooldown` or `cooldown <goal>`.
- Repeats: `<n>x <work> / <recovery>`. More parts are allowed; they alternate work and recovery, or use the words `hard` / `herstel`.
- A plain line like `12 km z2` is a single run.
- Goals: `45 sec`, `3 min`, `8 km`, `400 m`, `open`. Zone `z1` to `z5` is optional and adds a heart rate zone alert.
- Markdown, bullets and an intro line from a chatbot are ignored. `//` starts a note.

"Plan op Watch" replaces everything this app put on the Watch with the upcoming workouts of all events, earliest first, up to WorkoutKit's limit. "Op je Watch" on the home screen lists what WorkoutKit reports as scheduled (only this app's workouts).

## Check that it worked

- On the Watch: open Workout, scroll to Hardlopen buiten, tap the `...` button. The planned workouts are listed there. The one for today also appears at the top of the Workout app.
- On the iPhone: the Fitness app shows the planned workouts in the Workout tab.
- In the app: the "Op je Watch" list on the home screen, and a Watch icon next to each workout that landed.

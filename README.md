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

Write workouts the way you would say them. The app rewrites the text to its own short format and shows a preview before anything is saved.

- **One workout**: open an event, tap `+`, pick a date and describe it, for example `10 min inlopen, 5 keer 3 min hard met 2 min rust, uitlopen`.
- **A whole schedule**: `+` > "Importeer schema" and paste it. Dates (`1-12-2026`, `2026-12-01`) or day names (`Dinsdag: ...`, under `Week 2`) both work; with day names you pick the Monday week 1 starts. Edit the event name and start time in the preview. An event with the same name is replaced.
- **From Claude**: `+` > "Kopieer prompt voor Claude" gives a prompt that makes Claude answer in the exact short format. Free text from Claude works too.
- **Edit with Claude**: in an event, `...` > "Kopieer als tekst" gives the whole schedule in the short format.

What it understands:

- Warm-up: `inlopen`, `warming-up`, `warm`. Cool-down: `uitlopen`, `cooling-down`, `naar huis`, `in- en uitlopen 2 km`.
- Repeats: `5 keer`, `5x`, `5x3 min`, `6 versnellingen van 20 sec`, with the rest after `met`, `/` or in the next part (`2 min dribbelen ertussen`).
- Units: sec, min, uur, kwartier, half uur, km, m, meter, 5k.
- Zones: `z2` or `zone 2`, or from words: rustig/duurloop 2, tempo/racetempo 3, stevig/hard/drempel 4, sprint 5.
- Lines without time or distance (rest days, notes, intros) are skipped. Markdown and bullets are ignored.

The short format the app writes:

```
Zevenheuvelenloop
tijd 07:00

2026-12-01 Di intervallen
warmup 10 min z2
5x 3 min z4 / 2 min z2
cooldown
```

"Plan op Watch" replaces everything this app put on the Watch with the upcoming workouts of all events, earliest first, up to WorkoutKit's limit. "Op je Watch" on the home screen lists what WorkoutKit reports as scheduled (only this app's workouts).

## Check that it worked

- On the Watch: open Workout, scroll to Hardlopen buiten, tap the `...` button. The planned workouts are listed there. The one for today also appears at the top of the Workout app.
- On the iPhone: the Fitness app shows the planned workouts in the Workout tab.
- In the app: the "Op je Watch" list on the home screen, and a Watch icon next to each workout that landed.

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

Write workouts the way you would say them. The app reads the text with its own rules first (instant, offline). When the rules fail, or leave numbers they could not place, Apple Intelligence (on device, iOS 26+, when turned on) rewrites that part to the short format and the rules check it again. Workouts read this way are marked in the preview. Nothing is saved before you confirm.

- **One workout**: open an event, tap `+`, pick a date and describe it, for example `10 min inlopen, 5 keer 3 min hard met 2 min rust, uitlopen`.
- **A new event**: tap `+`. Give it a name, optionally a race date (shown as a countdown; that day's workout gets the finish flag) and a start time. Then paste a schedule or choose "Later toevoegen". "Prompt voor Claude" copies a prompt that already holds the event name, race date and today's date. Change name, date or time later in the event: `...` > "Wijzig naam en datum".
- **A pasted schedule**: Dates (`1-12-2026`, `2026-12-01`) or day names (`Dinsdag: ...`, under `Week 2`) both work; with day names you pick the Monday week 1 starts. Event names must be unique.
- **Edit with Claude**: in an event, `...` > "Kopieer als tekst" gives the whole schedule in the short format.

What it understands:

- Warm-up: `inlopen`, `warming-up`, `warm`. Cool-down: `uitlopen`, `cooling-down`, `naar huis`, `in- en uitlopen 2 km`.
- Repeats: `5 keer`, `5x`, `5x3 min`, `6 versnellingen van 20 sec`, with the rest after `met`, `/` or in the next part (`2 min dribbelen ertussen`). The count may also come after the steps (`3 min hard, 2 min zacht, herhaal 3x`, `en dat 4 keer`) or before them on its own line (`herhaal 5x:`).
- Units: sec, min, uur, kwartier, half uur, km, m, meter, mijl/mile, 5k. Number words like zes, tweemaal, vierhonderd.
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

In an event, each workout shows "Op Watch", or "vanaf <day>" when it shows up on the Watch later (the Watch shows the coming 7 days). Each week has a button "Voeg week toe" that adds just that week next to what is there; once added, "Week toegevoegd" lets you add it again or take it off.


## Check that it worked

- On the Watch: open the Workout app. At the top there is a block for this app (Rondje) with the workouts of the coming 7 days. Later ones show up by themselves.
- In the app: each workout in an event shows "Op Watch" or "Toegevoegd, op Watch vanaf <day>" once the iPhone handed it to WorkoutKit. The app cannot see the Watch itself.
- If nothing shows up: keep the Watch unlocked and near the iPhone, check the Watch runs watchOS 10 or later, and check that scheduling is allowed in the Watch app on the iPhone (Workout settings).

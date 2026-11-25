# Rondje

Personal iPhone app that puts structured runs in the Workout app on Apple Watch, using WorkoutKit's `WorkoutScheduler`. Workouts are grouped in goals ("doelen" in the app, stored as events: a race with its training schedule). The bundled `schedule.json` (Devil's Trail) is the first event.

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

Every text screen has a "Klaar" button above the keyboard, and scrolling down hides the keyboard.

Write workouts the way you would say them. The app reads the text with its own rules first (instant, offline). When the rules fail, or leave numbers they could not place, Apple Intelligence (on device, iOS 26+, when turned on) rewrites that part to the short format and the rules check it again. Workouts read this way are marked in the preview. Nothing is saved before you confirm.

- **One workout**: open an event, tap `+`, pick a date and describe it, for example `10 min inlopen, 5 keer 3 min hard met 2 min rust, uitlopen`.
- **A new goal**: tap `+` (or "Nieuw doel"). Rondje asks in a chat: one question at a time in bubbles, your answers on the right (tap one to change it). At the bottom there is always a chat field with suggested answers above it: tap one, or type ("13 december", "4", "15 km, 400 hoogtemeters", "1:55"). It asks the name (with quick picks), the big day (or none), and how to make the schedule: with AI, paste it yourself, or later. With AI it asks runs per week, current level, aim and wishes with big choice buttons, builds the prompt, then walks through copy, open Claude, ChatGPT or Gemini, and paste. It ends with an overview of the workouts and "Maak doel". For your own race (Anders, namelijk) the prompt asks the AI to look up the race's date, distance and elevation. Trailrun gets its own page for distance and elevation.
- **No goals yet**: the home screen is a three-page carousel (goal, schedule, Watch) with illustrations and a "Nieuw doel" button. An empty goal offers "Plak een schema" and "Training toevoegen".
- **Change the whole schedule**: in an event, `...` > "Wijzig schema" shows every workout as readable text ("1 dec 2026: Heuvels", "Warming-up 15 min in zone 2"). Edit it or paste a new schedule over it; the preview lists what is new, changed or gone. Saving keeps the name and race date and updates the Watch; a loader shows while the text is read and while the Watch is updated.
- **Change a workout**: open it and tap "Wijzig". The form opens with the date, name and the workout in the short format. If the old version was on the Watch, it is replaced.
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

In an event, a workout says "Op Watch" on its day once it is scheduled (the Watch shows a scheduled workout in the Workout app on its own day; the Watch app on the iPhone lists the coming 7 days), and "Bij workouts" when it was added without a date. The workout's own screen says whether and when it shows up. Swipe a workout left for "Op Watch" or "Van Watch". In an event, `...` > "Zet alles op Watch" adds every upcoming workout next to what is already there.

In a workout, "Voeg toe aan je workouts" opens Apple's preview; adding there puts it straight in your own workouts on the Watch, without a date. Apple does not tell the app whether you tapped add, so closing the preview counts as added and the list shows "Bij workouts". Tap "Weg" in the workout to undo.


## Check that it worked

- On the Watch: open the Workout app. At the top there is a block for this app (Rondje) with today's workout; each scheduled workout appears there on its own day. To see later ones on the Watch: tap the three dots on Rondje, then View More; they are under Upcoming. The Watch app on the iPhone shows what is scheduled for the coming 7 days.
- In the app: each workout in an event shows "Toegevoegd" or "Op Watch" once the iPhone handed it to WorkoutKit. The app cannot see the Watch itself.
- If nothing shows up: keep the Watch unlocked and near the iPhone, check the Watch runs watchOS 10 or later, and check that scheduling is allowed in the Watch app on the iPhone (Workout settings).

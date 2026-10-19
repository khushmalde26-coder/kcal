# Kcal quality check and competitor gap review (19 Oct 2026)

## Health of the code

| Check | Result |
|---|---|
| KcalCore unit tests | 35 passing (8 suites) |
| Debug and Release builds | Pass, no Swift warnings |
| Xcode static analyser | No issues |
| Remaining build warning | Portrait-only orientation (iPad multitasking only; iPhone-only app) |

### Fixed in this pass
- **Overnight date bug.** Today kept the date the app was opened, so food logged the next
  morning without relaunching went into yesterday. Today now moves to the new day when the
  app returns or the calendar day changes (unless you'd navigated to another day).
- **Missing privacy manifest.** Apple requires `PrivacyInfo.xcprivacy`; added (no tracking,
  UserDefaults reason CA92.1). The App Store privacy label still needs filling in.
- **Implausible measurements.** Height and weight had no limits (0 kg gave a nonsense plan).
  Onboarding now needs 120–230 cm and 30–400 kg; Settings shows a warning.

### Risks found, not fixed
1. **Meal photo logging is off.** It needs a small backend to hold the AI key (never ship
   keys in the app). This was one of the original requirements and is Cal AI's core feature.
2. **Food search limits.** Open Food Facts allows about 10 searches a minute per IP; outside
   the UK, USDA's DEMO_KEY is about 30 an hour per IP. Fine for testing, not for launch.
3. **No backup.** Everything lives on the phone. Deleting the app loses the log. Models are
   already CloudKit-compatible, so iCloud sync is mostly configuration (needs the paid
   developer account).
4. **Metric only.** UK users commonly weigh in stone and pounds, US users in pounds/feet.
5. **Dynamic Type.** The ring's big number uses fixed point sizes, so it doesn't grow with the
   user's text size setting. Most other text does.
6. **Earlier homemade items and portion-only staples.** Gram amounts in a saved homemade item
   are read as portions if a portion-only product later becomes that staple.

## Competitor features Kcal lacks

Sources: MyFitnessPal 2026 Winter Release; comparison reviews of Lose It!, MacroFactor,
Yazio, Cronometer and Cal AI (links in the project thread).

### Must have before launch
- **AI meal photo** (Cal AI, MyFitnessPal Meal Scan). Already built in the app; needs the
  backend.
- **Copy and repeat meals**: "log yesterday's breakfast again", copy a meal to another day,
  recent meals as one tap. Every major tracker has this; it's the biggest daily time saver.
- **Reminders**: gentle notifications to log meals and weigh in. Retention driver in all
  competitors.
- **Imperial units**: stone/lb and ft/in.
- **iCloud backup and sync.**
- **Privacy policy and App Store privacy label** (required for HealthKit apps).

### Strong differentiators to add next
- **Adaptive goal** (MacroFactor): adjust the daily target from logged intake versus the
  weight trend after 2–3 weeks. Kcal already has the trend maths; this is a natural next step.
- **Voice or text logging** (MyFitnessPal Voice Log, Cal AI descriptions): "two eggs on toast
  and a latte" → items. On-device speech plus the same backend as photos.
- **Home Screen and Lock Screen widgets** and a **Live Activity** for kcal left.
- **Weekly summary**: average intake, days on target, weight change, best and worst days.
- **Streaks and gentle milestones** (Lose It!, Cal AI).
- **Water tracking** (Yazio, MyFitnessPal).

### Nice to have
- Intermittent fasting timer (Yazio).
- Micronutrients beyond fibre, sugar, saturates and salt (Cronometer).
- Meal plans and recipe ideas (MyFitnessPal Premium+).
- Apple Watch app and Siri shortcuts ("log my coffee").
- Restaurant / chain menu data (MyFitnessPal's large crowd-sourced database).

### Where Kcal is already ahead
- UK government food data built in (instant, offline, accurate) instead of crowd-sourced entries.
- Homemade items built from the user's own staples (their milk, their bread).
- Nutrition label scanning with editable review, portion-only foods.
- Activity shown as earned calories on a fixed goal, counted at 75% to correct for watch
  overestimates.
- No account, no ads, data stays on the phone.

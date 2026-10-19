# Kcal

Native iPhone calorie tracker for weight loss. SwiftUI, iOS 26, Liquid Glass.

## Build

Requires a Mac with Xcode 26.

```sh
brew install xcodegen
cd kcal
xcodegen            # generates Kcal.xcodeproj from project.yml
open Kcal.xcodeproj
```

Core logic tests run without a simulator:

```sh
cd Packages/KcalCore && swift test
```

Optional: create `Config/Secrets.xcconfig` with `USDA_API_KEY = your_key` (free at
https://fdc.nal.usda.gov/api-key-signup). Without it the app uses `DEMO_KEY`, which
allows about 30 searches an hour.

## Structure

| Path | What |
|---|---|
| `Packages/KcalCore` | Pure Swift: label parser, energy maths, food database decoding. Unit tested. |
| `Kcal/Models` | SwiftData models: `Food` (per 100 g), `LogEntry` (snapshot of a portion), `WeightEntry`. |
| `Kcal/Services` | Open Food Facts and USDA client, on-device label OCR (Vision), meal photo client, settings. |
| `Kcal/Views` | Today, Add flows (search, barcode, label, meal photo), Progress, Settings and onboarding. |

## How logging works

- **Search**: your saved foods instantly, then USDA (generic foods) and Open Food Facts
  (packaged products) after a one second pause or on Return.
- **Barcode**: VisionKit live scanner. Checks your saved foods first, then Open Food Facts.
  Unknown products go straight to label scanning with the barcode attached, so the next
  scan of that product is found locally.
- **Nutrition label**: photo, on-device OCR with Vision, parser handles UK/EU (per 100 g
  and per serving columns, kJ/kcal, decimal commas) and US (per serving, % DV) layouts.
  The user always reviews the numbers before saving. The product is saved, then the
  portion screen logs it.
- **Meal photo**: client is written, but hidden until a backend exists. See below.

## Design notes

- Liquid Glass is used on controls and navigation (tab bar, floating quick add bar,
  primary buttons, toasts), not on content cards, which is Apple's guidance.
- Search lives in the iOS 26 search tab.
- Log entries copy the nutrients at log time, so editing a food never changes history.
- Goal: Mifflin-St Jeor maintenance minus a deficit, capped at 1% of body weight a week,
  floored at 1200 kcal (female) / 1500 kcal (male). Protein set at 1.8 g/kg.
- Weight is shown as a smoothed trend because daily readings swing with water.

## Known gaps before App Store

1. **Food data at scale.** Open Food Facts allows ~10 searches a minute per IP and USDA
   1,000 an hour per key shared by all users. Fine for a beta. For launch, either put search
   behind our own backend with caching, or license a database (FatSecret, Nutritionix, Edamam).
2. **Meal photo backend.** Needs a server holding the AI API key, App Attest, and rate limits.
3. **Open Food Facts licence.** Data is ODbL: attribution is in Settings; if we cache and
   redistribute their data from a backend, share-alike applies to that database.
4. **Not yet built**: app icon, HealthKit sync (weight in, energy out), widgets, reminders,
   editing a logged entry, custom food creation without a label, lbs/stone units,
   privacy policy and App Store privacy labels.
5. Label OCR assumes the photo is roughly straight. Tilted photos split rows badly.

## Colour and contrast

All colours live once in `Kcal/Assets.xcassets/Theme` (light and dark variants) and are read through `Kcal/App/Theme.swift`. WCAG 2 contrast ratios (AA: 4.5:1 body text, 3:1 large text and UI graphics):

| Use | Light | Ratio | Dark | Ratio |
|---|---|---|---|---|
| Text on background | Cocoa #4A3529 on Milk #FBF7F2 | 10.7 | Oat #F4EDE4 on #241A14 | 14.7 |
| Text on surface | Cocoa on Oat #F4EDE4 | 9.9 | Oat on #33261E | 12.6 |
| Secondary text on surface | #75614F on Oat | 5.1 | #BBA898 on #33261E | 6.4 |
| Button label on tint | Milk on Cocoa | 10.7 | #241A14 on Sand #E3D1BE | 11.5 |
| Ring: goal arc (UI) | Cocoa on Oat | 9.9 | Sand on #33261E | 9.8 |
| Ring: earned fill (UI) | #A9785C on Oat | 3.3 | Blush #D4AE96 on #33261E | 7.2 |
| "From activity" text | #8E5E43 on Oat | 4.7 | Blush on #33261E | 7.2 |
| Over (text and outer ring) | Terracotta #A4553A on Oat | 4.6 | #D9805F on #33261E | 5.0 |
| Macro bars: protein / carbs / fat | Cocoa / #A9785C / #8A7564 on Oat | 9.9 / 3.3 / 3.8 | Sand / Blush / #B89B80 on #33261E | 9.8 / 7.2 / 5.6 |

Blush #D4AE96 is 1.9:1 on Milk, so on light backgrounds it's decorative only (the logo dot) and never carries text or data. The Sand ring track (1.3:1) is decorative; the ring's state is also given as text ("kcal left" / "kcal over") and by shape: the earned zone starts after a gap, and going over adds a thinner ring outside.

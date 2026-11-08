# SnapCal

Take a picture of your paper calendar and SnapCal puts the handwritten events into your iPhone calendar.

## How it works

1. **Scan.** Tap **Scan Calendar** and point the camera at the month, or pick a photo you already took.
2. **Read.** SnapCal finds the printed dates. Then several free text readers built into the iPhone each read the handwriting in every day box:
   - Apple Vision, with spelling correction
   - Apple Vision, raw
   - Apple Live Text
   - a pass over the full page

   Where the readers disagree, SnapCal keeps the answer most of them agree on. On iPhones with Apple Intelligence, the phone's built-in AI also fixes misread words.
3. **Check.** You see every event it found next to a picture of the handwriting. You can fix anything, untick what you don't want, or add something it missed.
   - Events already in your calendar are unticked, so nothing gets added twice.
   - Printed holidays such as "Thanksgiving" are unticked.
4. **Add.** Tap **Add to Calendar**. If something looks wrong, there's an **Undo** button.

Everything runs on your phone. Photos aren't uploaded anywhere, and the app costs nothing to use.

## Getting the app (.ipa)

Every change to this repo builds a new `SnapCal.ipa` on GitHub's free Mac computers.

- Latest download: **Releases** → newest build → `SnapCal.ipa`
- Direct link: https://github.com/stickytoolz/snapcal/releases/latest/download/SnapCal.ipa

The `.ipa` is unsigned. Sideload it with your usual tool (AltStore, Sideloadly, etc.), which signs it for your phone.

Requires iOS 17 or newer.

## For developers

- The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- Build steps are in `.github/workflows/build.yml`.

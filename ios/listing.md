# App Store listing: (Witness) Protection

App record: App Store Connect app 6838787460, bundle ID `com.samuelling.witness`, SKU `com.samuelling.witness`.

| Field | Value |
|---|---|
| Name | (Witness) Protection ("Witness Protection" was taken) |
| Subtitle | TV-style face & voice disguise |
| Primary category | Photo & Video |
| Secondary category | Entertainment |
| Price | Free |
| Availability | All countries and regions except China mainland |
| Age rating | 4+ (every content question answered None / No) |
| Copyright | 2026 Samuel Ling |
| Support URL | https://linglab.org/witness/privacy.html#support |
| Marketing URL | https://linglab.org/witness/ |
| Privacy policy URL | https://linglab.org/witness/privacy.html |
| App Privacy | Data Not Collected |
| Content rights | Does not contain, show or access third-party content |
| Encryption | None (ITSAppUsesNonExemptEncryption = NO in the Info.plist) |

## Promotional text

Talk to the camera like a protected witness on the evening news: face pixelated, voice lowered, with a caption and live subtitles. All on your phone.

## Description

Witness turns your camera into a protected-witness interview from the TV news.

Point it at yourself and your face is found and pixelated automatically, following you as you move. Your voice is pitched down, or turned into a robotic vocoder, live as you talk. Add a lower-third caption and on-device subtitles, record a take, and save or share it.

• Face: mosaic, blur, black bar, or a full silhouette
• Voice: the classic pitch-down or a vocoder, adjustable while you listen
• Scene: blur the background, edit the lower-third caption, turn on live subtitles
• Everything runs on your device. Nothing you film or say is uploaded. No accounts, no ads, no tracking.

Witness is for fun and for the look of a TV interview. It isn't a guarantee of anonymity: a face that is turned away or partly covered can be missed, and a pitch-shifted voice can sometimes be shifted back.

## Keywords

anonymous,pixelate,blur,face,voice changer,vocoder,interview,disguise,news,mosaic,silhouette,privacy

## Notes for App Review

No account or sign-in is needed.

1. Tap "Use camera" and allow camera and microphone access. Your face is pixelated automatically and your voice is pitched down.
2. While it runs, change the options below the picture: Face (Mosaic, Blur, Bar, Silhouette), Scene (background blur, lower-third caption, live subtitles) and Voice (Pitch shift or Vocoder). "Hear it live" plays the disguised voice back; use headphones to avoid feedback.
3. "Record" makes a take; "Save / share" on a take opens the share sheet.

Live subtitles are optional and off by default. They use the iOS Speech framework with on-device recognition only (requiresOnDeviceRecognition), so iOS asks for Speech Recognition permission the first time; no speech leaves the device. Only if a device can't recognise speech offline does the app fall back to downloading the open-source Moonshine speech model (model data only) from huggingface.co. All of the app's code, and its face and person detection models, are inside the app bundle. Nothing the user films or says leaves the device.

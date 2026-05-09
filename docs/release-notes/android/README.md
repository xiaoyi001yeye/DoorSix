# Android Release Notes

Each Android release must include a user-facing release notes file before CI publishes the APK.

File name format:

```text
<versionName>+<versionCode>.md
```

Example:

```text
0.2.0+2.md
```

The CI release flow reads this file to populate the app update manifest `releaseNotes` field and the GitHub Release body. Keep the content short, user-facing, and suitable for display in the Android update dialog.

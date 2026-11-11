# How it works

- **Window tracking.** `CGWindowListCopyWindowInfo` gives System Settings' window frame
  without any permission. A timer in common run loop modes keeps the panels attached
  while the window moves, including during a drag.
- **Highlight.** With Accessibility permission, PermissionGuide reads the list's exact frame.
  Without it, the highlight is placed from System Settings' layout (measured on macOS 27)
  and covers the first two rows. Extension switches are found from the sheet's frame.
  Once the grant has gone through (the user clicked Later on "Quit & Reopen"), and
  briefly after authenticating, nothing is highlighted, because those rows aren't your app's.
- **Prompts.** Touch ID, password and "Quit & Reopen" windows are found in the window
  list and told apart by the order they appear in and their size. While "Quit & Reopen"
  is up, the guide waits for the user's answer even if the grant is already visible.
- **Probe.** For permissions that may need a relaunch, a fresh copy of the app reports
  what it has through its exit status (`PermissionGuideProbe`), at most every 1.5 seconds
  during a request and every 5 seconds otherwise, only while one is missing.
- **Drag.** The icon's pasteboard item is the app's file URL. Dropping it into a privacy
  list adds the app, the same as picking it with "+".
- **Sheets.** System Settings ignores deep links while a sheet is open, and it can't be
  closed without Accessibility. When one is open, PermissionGuide quits System Settings
  and reopens it on the right pane. While guiding a drag, the highlight hides whenever a
  sheet (such as the "+" file picker) covers the list.
- **Placement.** The panel docks to the right of the window, or to the left, or over the
  sidebar on screens too small for either. It works across displays and re-lays out when
  displays change.

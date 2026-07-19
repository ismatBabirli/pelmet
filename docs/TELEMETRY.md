# Telemetry

**TL;DR**

- One anonymous event per day. That is the entire event stream.
- Opt-out: an in-app notice appears before anything is ever sent.
- Data: app version, macOS version (major.minor), `arm64` or `x86_64`, notch
  yes/no, a handful of feature on/off booleans, whether the previous session
  ended cleanly, and a random resettable install ID.
- Destination: PostHog Cloud US. IP addresses are discarded.
- Off switches: the Settings toggle, one `defaults` command, or `DO_NOT_TRACK=1`.

## Why we collect anything

Pelmet ships outside the App Store, so there is no dashboard telling us how many
people run it, which macOS versions to keep supporting, or which features earn
their maintenance. One tiny event per day answers all of that: an install count,
version adoption, the macOS and chip spread, which features are switched on, and
a crash rate. That is why there is nothing else here.

## Exactly what is sent

A single `heartbeat` event, at most once per UTC day, as a plain HTTPS `POST` to
`https://us.i.posthog.com/i/v0/e/`:

```json
{
  "api_key": "<public write-only project key>",
  "event": "heartbeat",
  "distinct_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
  "timestamp": "2026-07-13T00:04:11Z",
  "properties": {
    "$process_person_profile": false,
    "$geoip_disable": true,
    "app_version": "0.3.0",
    "macos": "15.5",
    "arch": "arm64",
    "notch": true,
    "shelf_enabled": true,
    "one_click_enabled": false,
    "auto_rehide": true,
    "manages_items": true,
    "prev_session_clean": true
  }
}
```

The exact same JSON is visible live in **Settings > General > Privacy > "What
exactly is sent?"**, rendered from the same code that builds the wire payload,
so the preview cannot drift from reality.

| Field | Example | Why we need it |
|---|---|---|
| `distinct_id` | random UUID | Count one Mac once per day/month. Derived from nothing, resettable. |
| `app_version` | `0.3.0` | Version adoption; deciding when an old version can be dropped. |
| `macos` | `15.5` | Which macOS versions to keep supporting. Major.minor only. |
| `arch` | `arm64` | Apple silicon vs Intel split. |
| `notch` | `true` | Whether notch-specific features matter to real users. |
| `shelf_enabled` | `true` | Is the Shelf used? |
| `one_click_enabled` | `false` | Is the opt-in Accessibility feature used? |
| `auto_rehide` | `true` | Is auto re-hide left on? |
| `manages_items` | `true` | Has this install ever actually hidden icons? |
| `prev_session_clean` | `true` | Crash rate: did the previous session end cleanly? |
| `$process_person_profile` | `false` | PostHog directive: never build a person profile (stay anonymous). |
| `$geoip_disable` | `true` | PostHog directive: skip server-side geo lookup. |

## What we NEVER collect

- **Your IP address** is discarded on arrival and geo lookup is disabled; we
  never see or store it.
- **No names, emails, usernames, or device names.**
- **No file paths, filenames, or window titles.**
- **Nothing about your menu bar contents**: not the names, not the count, not the
  icons of the apps you run. Pelmet's Shelf reads other apps' names locally to
  draw its rows; that data never enters telemetry. The payload is a fixed struct
  and a unit test fails the build if a field is added without updating this
  document.
- **No unique hardware identifiers**: no serial number, no exact model
  identifier, no MAC address.
- **No location, locale, or timezone.**
- **No behavioral stream**: no clicks, no timings, no session lengths, no hotkey
  usage.

## When it is sent

Once per UTC day, checked at launch and hourly while running. The very first send
only happens after the in-app notice has been shown, and never sooner than the
next launch or 24 hours after you saw it, whichever comes first, so you always
have a real window to turn it off first.

## The install ID

A random UUID that Pelmet invents on the first send, derived from nothing about
you or your Mac. It exists only so one install counts once per day and month. You
can generate a fresh one any time with **Settings > General > Privacy > "Reset
Install ID"**; resetting unlinks all past pings from the new one. Turning
telemetry off forgets the ID entirely.

## Where the data goes

PostHog Cloud US. The request is a plain HTTPS `POST`; there
is no SDK. The API key embedded in the source is a public, write-only ingestion
token: it can only send events, never read anything back. Events are flagged so
PostHog creates no person profiles, and the project is configured to discard
client IPs.

## Retention

Raw events are deleted after at most 12 months. We work from aggregates.

## Public numbers

The dashboard built from this data is shared publicly (link to be added with the
0.3.0 release), so you can see exactly what we see.

## How to turn it off

1. **Settings > General > Privacy > "Share anonymous usage statistics".**
2. `defaults write com.ismatbabirli.Pelmet telemetryEnabled -bool NO`
   (works before first launch too).
3. Set `DO_NOT_TRACK=1` in the app's environment. Note: apps launched from Finder
   do not inherit your shell profile, so use `launchctl setenv DO_NOT_TRACK 1` or
   the `defaults` command above.

Also: `swift run` and debug builds never send anything, and blocking
`us.i.posthog.com` (Little Snitch, Pi-hole, a firewall) blocks it entirely and
silently.

## Crash reports stay on your Mac

Pelmet never uploads crash data. After a crash, the next launch offers to open a
GitHub issue prefilled with your Pelmet and macOS versions, and reveals the crash
report (`.ips`) in Finder so you can look it over and attach it yourself, or just
close the tab. The daily ping carries a single boolean, `prev_session_clean`, and
nothing from the trace.

## The sending code

- [`Sources/PelmetCore/Telemetry/TelemetryPayload.swift`](../Sources/PelmetCore/Telemetry/TelemetryPayload.swift):
  the frozen payload struct and its JSON encoding.
- [`Sources/Pelmet/Telemetry/TelemetryManager.swift`](../Sources/Pelmet/Telemetry/TelemetryManager.swift):
  the gates and the one `URLSession` call.
- [`Tests/PelmetCoreTests/TelemetryPayloadTests.swift`](../Tests/PelmetCoreTests/TelemetryPayloadTests.swift):
  the schema test that pins the exact field set.

## Changes

Any new or changed field requires a change to this file and a `CHANGELOG.md`
entry in the same pull request. That rule is written into `CONTRIBUTING.md`, and
the schema test above fails the build if the payload and this document drift
apart.

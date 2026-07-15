# Security & credentials — owner action required

_Status as verified on 2026-07-13. These are project-owner actions; none of
them can be fully resolved by code changes in this repo._

## 1. GitHub PAT leaked into git history — NOT fully resolved

A GitHub personal access token (`ghp_Kx17…`, full value visible in history)
was hardcoded in `plugins/flutter_meta_wearables_dat/android/build.gradle`
and **committed and pushed**: commit `6a63cca` is on `origin/jitesh` at
`github.com/CAPJITESH/meta_glasses_langchain`.

Current state:
- The token has been removed from the working copy (the file now reads
  credentials from gradle properties / environment — see §3).
- A revoke was *triggered* in a prior session, but has not been confirmed.
- Unauthenticated access to the repo returns 404, so the repo appears to be
  **private**, not public. That lowers exposure, but note that GitHub's
  automatic secret-scanning revocation applies to public repos — a private
  repo means the token was likely **not** auto-revoked.

Owner must:
1. **Confirm the token is revoked** at GitHub → Settings → Developer settings
   → Personal access tokens. If in doubt, revoke again — it is idempotent.
2. Decide about history: as long as the repo stays private and the token is
   revoked, scrubbing history is optional hygiene. **If the repo is ever made
   public, the history must be rewritten first** (e.g. `git filter-repo`)
   because commit `6a63cca` contains the token verbatim.

## 2. Meta DAT credentials are placeholders — glasses cannot connect

`android/app/src/main/AndroidManifest.xml` still has:

- `com.meta.wearable.mwdat.APPLICATION_ID` = `TODO_REPLACE_WITH_REAL_MWDAT_APPLICATION_ID`
- `com.meta.wearable.mwdat.CLIENT_TOKEN` = `TODO_REPLACE_WITH_REAL_MWDAT_CLIENT_TOKEN`

The Flutter↔Kotlin bridge itself was verified correct in a prior session; the
only thing standing between the app and a real glasses connection is real
values from Meta's Wearables Device Access Toolkit developer registration.
This is an account/registration task, not an engineering task.

## 3. mwdat Maven dependencies currently cannot resolve

When the PAT was scrubbed, the GitHub Packages credentials became empty
strings, so `com.meta.wearable:mwdat-*` fails to resolve and **any Android
build fails at dependency resolution** (unless artifacts are already in the
local Gradle cache). The plugin's `build.gradle` now reads credentials from,
in order:

1. `gpr.user` / `gpr.token` in `~/.gradle/gradle.properties` (recommended —
   lives outside the repo), or
2. `GITHUB_ACTOR` / `GITHUB_TOKEN` environment variables.

Owner must create a fresh, **minimal-scope** PAT (only `read:packages`) and
put it in `~/.gradle/gradle.properties`. Do not put it back in any committed
file.

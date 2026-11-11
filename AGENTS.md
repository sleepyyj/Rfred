# Agent instructions

## Commit messages

Every commit must describe the full set of changes it contains. Do not use a single subject line for a multi-change commit and hide the other work in the diff.

- Subject: `type: ` plus one short imperative sentence naming the main goal of the commit. The type is what the release workflow reads.
- Body: a bullet list covering every feature, fix, UI change, documentation update, and test in the commit.
- When a commit contains multiple features, keep the subject as a summary and list every feature in the body.
- Do not omit small changes. Describe user-visible behavior, data migrations, and compatibility changes.
- Prefer splitting unrelated changes into separate commits.

The subject starts with a semver type, then the imperative sentence. A push to `main` tags the next release from that type. The tag is `vMAJOR.MINOR.PATCH`. The release workflow stamps `Info.plist` for the DMG and tags the pushed commit. It does not add a "Set version" commit.

- `feat: ...` increments minor and resets patch. `feat: Show clipboard image previews`
- `fix: ...` increments patch. `fix: Skip a duplicate paste`
- `chore:`, `docs:`, `refactor:`, `test:`, and `ci:` also increment patch, and still publish a release.
- A subject with `!` after the type, or a body line `BREAKING CHANGE:`, increments major and resets minor and patch.
- Several commits in one push use the highest change: major, then minor, then patch.
- A subject without a type is a patch. Put `[skip ci]` in the subject to push without a release.

`Info.plist` in git keeps the last version someone committed. The DMG and the GitHub tag carry the released version.

## App name

The app is Rfred, and every identifier uses that name: the bundle identifier `dev.jim.rfred.local`, the `Rfred Codesign` certificate, the `RFRED_CODESIGN_*` secrets, the `RfredLocal` data folders, and the `rfredlocal://` URL scheme. Nothing reads the earlier `Jfred` names or folders, and there is no migration from them.

## Code signing

Release builds sign `Rfred.app` with one self-signed certificate, common name `Rfred Codesign`. The designated requirement is:

```text
identifier "dev.jim.rfred.local" and certificate leaf = H"0bb33749a10bc56e0700ff9f1a569fa9c1f8d4cc"
```

macOS stores Desktop, Documents, and Downloads consent against that requirement, not against the app name or the install path. `codesign --sign -` sets the requirement to the build's cdhash. Every GitHub Actions runner then produces a different identity, and each installed update asks for those folders again.

The leaf hash comes from the certificate. Importing the same certificate on every runner keeps the hash stable, including across version bumps. `scripts/codesign-app.sh` signs with it and checks the requirement. `scripts/build-app.sh` calls that script. The release workflow refuses to build a DMG when the certificate secrets are missing, so a release cannot silently fall back to an ad-hoc signature.

The private key is not in git.

- Local copy: `~/.config/rfred/codesign/rfred-codesign.p12`, with the password in `~/.config/rfred/codesign/password`. A local `scripts/build-app.sh` uses these files when they exist.
- Actions secrets: `RFRED_CODESIGN_P12` (base64 of the same `.p12`) and `RFRED_CODESIGN_PASSWORD`.

Do not generate a replacement certificate. A new certificate is a new leaf hash, and the next update asks for folder access again. The certificate is not an Apple Developer ID and the app is not notarized. Gatekeeper still treats a freshly downloaded copy as an unidentified developer; the in-app updater removes the quarantine attribute before it replaces `Rfred.app`. The signature still has to pass `codesign --verify --deep --strict` against the designated requirement above, which is what the updater checks before swapping the bundle. An ad-hoc signature or another certificate is refused. `AppUpdateFeed.signingCertificateLeafHash` holds the leaf hash; it must match the certificate that signs releases.

`scripts/codesign-app.sh` signs with the hardened runtime (`--options runtime`) and `Resources/Rfred.entitlements`, and fails when the runtime flag is missing. The only entitlement is `com.apple.security.automation.apple-events`, which the hardened runtime requires for the AppleScript commands. Do not add `allow-dyld-environment-variables`, `disable-library-validation`, or `get-task-allow`; they let another process load code into Rfred and use its Accessibility and folder grants.

The in-app updater reads releases from `sleepyyj/Rfred` (`AppUpdateFeed.owner` and `AppUpdateFeed.repo`).

Example:

```text
feat: Rebuild workflows around Alfred object graphs

- Replace the flat action model with Alfred objects, connections and uidata
- Add Script Filter JSON/XML handling and graph execution
- Support multiple output connections and workflow-relative scripts
- Rework the Workflows pane, object palette and configuration sheets
- Fix disabled workflow styling and Configure Workflow behavior
- Add REA evidence, documentation and regression tests
```

# App identity

| | |
|---|---|
| App name | Duck Studio |
| Bundle identifier | `com.duckstudio.ios` |
| Team | `WYGG3JXWMG` |
| Platform | iPhone only, portrait, iOS 17+ |
| Encryption | `ITSAppUsesNonExemptEncryption=false` |

The identifier **already exists in the Apple Developer portal** — it was created
by hand. Do not create another one, and do not let `xcodegen` invent a different
string: `project.yml` must produce exactly `com.duckstudio.ios` or the archive will fail
provisioning at the last step of a long build, which is the most expensive place
to find a typo.

```yaml
# project.yml
options:
  bundleIdPrefix: com.duckstudio
targets:
  DuckStudio:
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.duckstudio.ios
        DEVELOPMENT_TEAM: WYGG3JXWMG
```

The planning documents in this repo were written before the identifiers were
registered, so README.md carried a guessed value and have been corrected to match the portal.

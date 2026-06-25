# GitHub Actions Packaging Research

## Sources

* GitHub-hosted runners reference: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
* Workflow syntax for GitHub Actions: https://docs.github.com/actions/using-workflows/workflow-syntax-for-github-actions
* Installing Apple certificates on macOS runners: https://docs.github.com/actions/deployment/deploying-xcode-applications/installing-an-apple-certificate-on-macos-runners-for-xcode-development
* actions/checkout releases: https://github.com/actions/checkout/releases
* actions/upload-artifact releases: https://github.com/actions/upload-artifact/releases

## Decisions

* Use explicit macOS runner labels instead of `macos-latest` so packaging does not drift when GitHub changes the alias.
* Build both `macos-26` and `macos-26-intel` artifacts to cover Apple Silicon and Intel during early packaging.
* Use current official action majors from the upstream repositories:
  * `actions/checkout@v6`
  * `actions/upload-artifact@v7`
* Keep the default artifact unsigned for now. Signing and notarization require Apple certificates, provisioning material, and repository secrets.
* Support two packaging paths:
  * Xcode archive when `RIGHTTOOL_XCODE_PROJECT` and `RIGHTTOOL_XCODE_SCHEME` are configured.
  * SwiftPM preview `.app` bundle while the repo does not yet contain a complete Xcode app project.

## Implications

The GitHub Actions workflow can start producing downloadable artifacts immediately, but the current preview bundle is not a final distributable Finder integration package. A signed app with embedded Finder Sync `.appex` requires a complete Xcode project and signing configuration.

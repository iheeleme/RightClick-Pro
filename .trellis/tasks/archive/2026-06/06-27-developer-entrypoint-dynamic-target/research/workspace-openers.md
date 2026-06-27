# Workspace Openers Research

## Goal

Support developer shortcut entries for apps that are not installed on this machine by using source-backed CLI information instead of only local bundle inspection.

## Sources Checked

- VS Code official CLI docs: https://code.visualstudio.com/docs/configure/command-line
  - Documents `code --help`, `code .`, opening files/folders/projects, and `code-insiders`.
- Zed official CLI reference: https://zed.dev/docs/reference/cli.html
  - Documents `zed [OPTIONS] [PATHS]...` and opening a directory as a workspace.
- Sublime Text official command-line docs: https://www.sublimetext.com/docs/command_line.html
  - Documents `subl` for opening files and projects.
- JetBrains IntelliJ IDEA official command-line docs: https://www.jetbrains.com/help/idea/working-with-the-ide-features-from-command-line.html
  - Documents opening files/projects from command line and macOS/Toolbox launcher scripts.
- Codex local first-party evidence:
  - `/Applications/Codex.app/Contents/Resources/codex --help`
  - Documents `codex app [OPTIONS] [PATH]` and describes `PATH` as the workspace path for Codex Desktop.
- VS Code local first-party evidence:
  - `/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code --help`
  - Documents `code [options] [paths...]`.

## Supported Candidate Strategy

- Codex:
  - Bundle identity: `com.openai.codex` or app/title containing `codex`.
  - Candidate: `Contents/Resources/codex app <workspace>`.
- VS Code family:
  - VS Code: `Contents/Resources/app/bin/code <workspace>`.
  - VS Code Insiders: `Contents/Resources/app/bin/code-insiders <workspace>`.
  - VSCodium: `Contents/Resources/app/bin/codium <workspace>`.
  - Cursor: `Contents/Resources/app/bin/cursor <workspace>`.
  - Windsurf: `Contents/Resources/app/bin/windsurf <workspace>`.
  - Trae: `Contents/Resources/app/bin/trae <workspace>`.
- JetBrains family:
  - Product-specific launchers such as `idea`, `webstorm`, `pycharm`, `goland`, `clion`, `datagrip`, `rider`, `rubymine`, `phpstorm`, `rustrover`, and `fleet`.
  - Probe app-bundled `Contents/MacOS/<launcher>` and `Contents/bin/<launcher>[.sh]`.
- Zed:
  - Probe app-bundled CLI locations, then global `zed` paths.
- Xcode:
  - Prefer `/usr/bin/xed <workspace>`, then app fallback.
- Sublime Text:
  - Probe `Contents/SharedSupport/bin/subl <workspace>`.
- TextMate:
  - Probe `Contents/Resources/mate`, then `mate` global paths.
- Nova:
  - Probe app-bundled `nova`, then global `nova` paths.

## Runtime Rules

- All candidates are checked with `FileManager.isExecutableFile(atPath:)`.
- If no candidate exists, keep previous `NSWorkspace.open` behavior.
- For workspace CLI apps, selected files resolve to their parent directory.
- The app picker still stores the app bundle identifier only; runtime lookup uses Launch Services to find the user's installed app.

## Notes

- Cursor, Windsurf, and Trae are handled as VS Code-family apps through package-local CLI helpers because their public app-bundle docs are less stable than VS Code/Zed/Sublime/JetBrains docs.
- This is intentionally not a built-in default app list expansion. Users still add local apps through the app picker; the opener makes those entries behave correctly when the app is installed on their machine.

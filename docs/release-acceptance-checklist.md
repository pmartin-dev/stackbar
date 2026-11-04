# Release acceptance checklist

Run these checks against the archived app and the DMG, not only from Xcode:

- [ ] Launch a project using the configured zsh shell and another using bash; verify the commands run in the selected project folder without a TTY.
- [ ] Launch a command that starts a child process, then stop it; verify the process group exits and logs remain available.
- [ ] In Preferences, click Add Project; verify the folder picker opens immediately, then the new card is prefilled with the folder name and detected commands (cancel adds nothing); verify it auto-saves once name, folder and launch command are valid, and that invalid edits show an inline error without saving.
- [ ] In the menu-bar popover, verify each project shows a single play or stop button matching its state, plus restart while running.
- [ ] Remove or rename a project's folder after configuration; verify the play button is disabled and its help text explains why.
- [ ] With an existing schema v1 `projects.json`, launch Stackbar; verify projects load as single-service projects and are rewritten as schema v2 on the next edit.
- [ ] Add a second service (name, optional subfolder, launch/stop commands) and a project stop command; verify the project row has no global play/stop, each service starts and stops on its own, and the project stop command runs when the last running service is stopped.
- [ ] In the menu, verify multi-service projects always list their services, and that each service shows its own status, play/stop, logs, URL and restart, and that stopping one service leaves the others running.
- [ ] Choose or drop a folder containing package.json/Makefile/compose files on a new project; verify the detected-commands checklist opens with dev/start-like commands pre-checked, that "Add N Services" creates them, and that "Detect" re-runs detection without duplicating existing commands.
- [ ] In the popover, verify hovering a project row shows an open-folder and a copy-path icon (hidden otherwise) (the path lands in the clipboard, a checkmark confirms it) without overlapping other icons; after a service fails, verify a clear-errors icon appears and resets the error status and messages.
- [ ] In Preferences, verify each project card matches the popover style (live status dot, play/stop, folder/trash on hover, click to expand) and that deleting a running project asks for confirmation inside its card.
- [ ] With a project running, test Quit and Cmd-Q: cancel leaves Stackbar and the process running; confirm stops all projects before Stackbar exits.
- [ ] Force a stop failure during termination; verify Stackbar stays open and identifies the failed project.
- [ ] Verify normal-stop and error notifications independently, including the first-launch permission prompt and the denied-permission instructions; click an error notification and verify the service log window opens.
- [ ] Start a service whose port is already taken; verify the error reads "Port … is already in use by another process." instead of the exit status.
- [ ] Enable launch-at-login from the ad hoc-signed release app; verify the macOS login-item status and the app after logging in again.
- [ ] Install the DMG by dragging Stackbar to Applications; verify the expected Gatekeeper warning and the documented **Open Anyway** flow.
- [ ] Verify the menu-bar extra uses the same safe termination path when macOS removes it.
- [ ] Start a server outside Stackbar on a service port (configured or previously detected), then launch the service; verify the warning names the process and PID, and that Stop It and Launch, Launch Anyway and Cancel behave as labeled.
- [ ] Launch a service, force-quit Stackbar (Activity Monitor), relaunch it; verify the service shows "Running (logs unavailable)" and can be stopped.
- [ ] Verify the menu bar icon shows the running service count and turns red after a failure, then back to normal after Clear errors.
- [ ] Verify multi-service project rows no longer show a service count under the name.

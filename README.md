# Stackbar

Stackbar is a native macOS menu bar app to start, stop and monitor your local development projects
in one click: front ends, APIs, Docker stacks, mock servers and anything else you usually run in a
terminal tab.

<!-- Screenshot: menu bar popover (docs/images/popover.png) -->
<!-- Screenshot: Settings window (docs/images/settings.png) -->

**Status:** early development. Requires macOS 26 or newer (Apple Silicon or Intel).

## Features

- **One-click play/stop** for every project from the menu bar, with a live status dot.
- **Multi-service projects**: run a front end, an API and a mock server side by side, each with its
  own play/stop button.
- **Automatic command detection**: pick a folder and Stackbar suggests the commands to run.
- **Logs** for each service, kept in memory, with the local URL detected from the output
  (`http://localhost:4200`…) and a button to open it.
- **Open folder**, **copy path**, **clear errors** (after a failure), **restart** and **open in browser** actions on hover.
- **Notifications** when a project stops normally or with an error; click an error notification to open its logs.
- **Clear error messages**, e.g. "Port 8000 is already in use by another process." instead of a bare exit status.
- **Port check before launch**: if the service port is already taken, Stackbar shows which process
  holds it and lets you stop it and launch, launch anyway or cancel.
- **Menu bar status**: the icon shows how many services are running and turns red after an error.
- **Crash recovery**: services left running after Stackbar crashed or was force-quit are picked up again
  on the next launch (shown as running with logs unavailable), so you can still stop them.
- **Launch at login** for Stackbar itself (projects never start automatically).
- **Safe quit**: quitting Stackbar stops your running projects first, so no orphan process keeps a
  port busy.

## Install

1. Download `Stackbar.dmg` from the GitHub Releases page.
2. Open it and drag `Stackbar.app` to `Applications`.
3. Open Stackbar. macOS will block the first launch (see below).

There is no auto-updater; check GitHub Releases for new versions.

### Why macOS blocks the first launch

Releases are signed ad hoc and **not notarized**: notarization requires a paid Apple Developer
Program membership (99 USD/year), which this project does not use. There is no other way to make
Gatekeeper trust a downloaded app, so you need to allow it once, using either option:

- **System Settings > Privacy & Security**, then **Open Anyway** next to the Stackbar message, and
  confirm.
- Or in Terminal: `xattr -dr com.apple.quarantine /Applications/Stackbar.app`

You can also build it yourself from the sources (see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)); local
builds are not quarantined.

Because each build gets a new ad hoc signature, macOS may ask again for permissions after an update
(notifications, **Launch at login**).

## Getting started

1. Click the Stackbar icon in the menu bar, then **Preferences...**.
2. Click **Add Project** and choose your project folder. The name is filled from the folder.
3. Stackbar scans the folder and lists the commands it found. Likely servers (`dev`, `start`,
   `serve`, `docker compose up`…) are pre-checked; click **Show N more commands** to see the rest.
4. Keep the ones you want and click **Add N Services**. The project is saved automatically.
5. Back in the menu bar, press **▶** to start it and **■** to stop it. For a project with several
   services, use the play/stop button of each service listed under it.

You can also drag a folder onto a project card, or click **Detect** later to scan again (existing
commands are not duplicated).

## Configuring a project

Each project has a name, a folder and one or more **services**:

| Field | Description |
|---|---|
| Service name | Label shown in the menu (only when a project has several services). |
| Subfolder | Optional folder, relative to the project, where the service runs (e.g. `frontend`). |
| Launch command | Any shell command, e.g. `pnpm start` or `docker compose up`. |
| Stop command | Optional. Runs before Stackbar terminates the service, e.g. `docker compose down`. |
| Port | Optional. Checked before launch; when empty, the last port detected in the logs is used. |
| Project stop command | Optional, multi-service only. Runs when the last running service is stopped. |

How commands run:

- Commands run in your login shell (**zsh** or **bash**), in interactive login mode, so your
  `PATH`, aliases and tools such as `mise`, `nvm` or `asdf` are available as in Terminal.
- There is no terminal attached: commands that wait for keyboard input will not work.
- Stopping a service runs its stop command (30 s max), then terminates the whole process group and
  waits up to 10 s. If something survives, Stackbar keeps the service marked as running with an error
  instead of pretending it stopped.
- A project can only run once at a time, and two projects cannot share the same folder.

## Command detection

Only the root of the folder is scanned. Supported sources:

| Source | Commands proposed |
|---|---|
| `package.json` | Every script, run with `pnpm`, `yarn`, `bun run` or `npm run` depending on the lockfile. Empty, separator and placeholder scripts are skipped. |
| `Makefile` | Every target (special and pattern targets are skipped). |
| `compose.yaml` / `docker-compose.yml` | `docker compose up`, with `docker compose down` as stop command. |
| `Procfile` | Every entry. |
| `Taskfile.yml` / `Taskfile.dist.yml` | Every task, as `task <name>`. |
| Gradle / Maven | `bootRun` or `spring-boot:run` for Spring Boot, `run`, build and test (wrappers are used when present). |
| `Cargo.toml` / `go.mod` | `cargo run`, `go run .`, tests and build. |
| Python | `manage.py runserver` (Django), `uvicorn` for a FastAPI `main.py`, prefixed with `uv run` or `poetry run` when relevant. |

Names starting with `dev`, `start`, `serve`, `run`, `up`, `watch` or `preview` are pre-checked,
unless they look like teardown or build tasks (`dev:down`, `start:build`…). You can edit or remove any
command afterwards.

## Data and privacy

- Projects are stored in `~/Library/Application Support/Stackbar/projects.json`, readable by your
  user only.
- Running services are tracked in `running.json` in the same folder (process group identifiers only),
  so they can be recovered after a crash. The file is removed when nothing runs.
- The last port detected for each service is kept in Stackbar's preferences.
- Logs stay in memory (up to 10 MiB per service) and are discarded when Stackbar quits.
- Stackbar sends nothing over the network.

## Troubleshooting

- **The play button is grayed out**: hover it to see why. Usually the folder was moved or deleted, or
  a launch command is empty.
- **`command not found`**: the tool is not on the `PATH` of your login shell. Check that it works in a
  new Terminal window, and that it is set up in `~/.zprofile` or `~/.zshrc` (or the bash equivalents).
- **A service does not stop**: add a stop command (e.g. `docker compose down`), or check the logs for
  a process that ignores termination signals.
- **Port already in use**: another process listens on the service port, often the same server started
  from a terminal. Use **Stop It and Launch** in the warning, or stop it yourself.
- **"Running (logs unavailable)"**: the service was recovered after Stackbar crashed; its earlier
  output is lost. Restart it to get logs again.
- **No notifications**: enable Stackbar in **System Settings > Notifications**.
- **Launch at login needs approval**: enable Stackbar in **System Settings > General > Login Items**.

## Contributing

Build instructions, architecture and release process are in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## License

Stackbar is available under the MIT license. See [LICENSE](LICENSE). Third-party dependencies are
listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

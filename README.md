# vibe-apps

Public monorepo for vibe-coded apps. Each project lives in its own directory under `apps/`.

## Apps

| App | Description | Tech |
| --- | --- | --- |
| [Rock Master RC](apps/rock-master-rc/README.md) | Offline BLE controller for the Wonder Toys Rock Master RC car. | Flutter (Android and iOS) |

## How to add a new app

1. Create `apps/<app-name>/` and put that project there. Leave build outputs, keystores, `.env`, and `local.properties` untracked. The root `.gitignore` already covers the usual Flutter, Android, iOS, Node, and Python outputs.
2. Add a row to the table above: the app name (linked to its README), a one-line description, and the tech stack.
3. If the app needs CI, add `.github/workflows/<app-name>.yml` and limit its `paths` filter to `apps/<app-name>/**` and that workflow file. Path filters are what keep one app's workflow from running when another app changes. Tag pushes ignore path filters, so give each app its own tag pattern (Rock Master RC uses `rock-master-rc-v*`).

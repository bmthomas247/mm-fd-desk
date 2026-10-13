# Moose Freshdesk Desk — RUNBOOK

Site: https://bmthomas247.github.io/mm-fd-desk/ (GitHub Pages, public repo `bmthomas247/mm-fd-desk`, code only)
Data: Supabase project **Moose Management - Maintenance**, tables `fd_items`, `fd_drafts`, `fd_actions`, `fd_runs`
(Free plan allows 2 projects; Maintenance + Rates already use them, so this desk shares Maintenance.)
Source: Dropbox `17-Claude Program Builds\fd-desk\` (this folder). Double-click `INSTALL_fd.bat` here to install or update.
Programs: `C:\Users\Kim\Documents\moose-track-sync\fd_desk\` on the ThinkStation
Status files (Claude reads these): Dropbox `12-TRACK Software\Maintenance Desk Feeds\fd-deploy.json`, `fd-status.json`

## Sign-in
- Same accounts and passwords as the maintenance site. Only `allowed_users` with role **admin** see anything.

## Where the data comes from (fd_sync.py, task "Moose FD Sync", every 15 min 6am–10pm)
- Uses the daily brief's own code and settings in `moosedaily` (`config.local.yaml` keys, `daily.yaml` rules). Change what counts there, not here.
- **My tickets**: every open ticket assigned to Brandon. Claude writes a status line, a reply and a close-out email for each one; it redrafts only when the ticket changes (20 per run max). Facts it can't verify show as `[CONFIRM: …]`.
- **Eyes on**: the brief's sections (decisions, escalations, money, mentions, the three Asana boards, worth a glance) plus tickets the Freshdesk key's agent is watching.
- **Calendar**: Outlook (Graph, 2 weeks out) plus Freshdesk due times.
- **Spam**: the Freshdesk spam folder.
- A source that fails doesn't blank the others; the header says which one couldn't be read.

## Writes
- Only the site's buttons write to Freshdesk (Send reply, Send and close, Not spam), only for admins, each after a confirm. Logged in `fd_actions` (append-only). Function: `fd-action`.
- The sync itself only reads. The sorting bot (`moosebot`) still owns every automatic write.
- Nothing is deleted: tables block deletes; gone items get `active = false`.
- Close sets status 5 (Closed). For Resolved instead, add `FD_CLOSE_STATUS=4` to `maintenance_desk\desk.env` and re-run `deploy_fd.bat`.

## Rebuild / redeploy
- `INSTALL_fd.bat` (in Dropbox) copies this folder to the ThinkStation and runs `deploy_fd.bat`.
- `deploy_fd.bat` — safe to re-run: adds the fd_* tables, stores the Freshdesk key as a function secret, deploys `fd-action`, adds this site to the sign-in redirect list (maintenance settings untouched), pushes the web files, verifies, writes `fd-deploy.json`, runs a first sync, registers the schedule.
- Keys stay where they already are: `maintenance_desk\desk.env` / `maint.env` and `moosedaily\config.local.yaml`. Claude never types keys.
- Test without writing anything: `python fd_sync.py --dry`.

## Optional settings (`maintenance_desk\desk.env`)
- `FD_SIGNATURE` reply sign-off (use `\n` for a new line), default `Brandon\nMoose Management`
- `FD_MODEL` Claude model for drafts (default: the brief's `digest.model`)
- `FD_CALENDAR_DAYS` default 14; `MOOSEDAILY_DIR` if moosedaily lives somewhere else

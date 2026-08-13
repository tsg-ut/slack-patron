# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Repository is a fork — pull request policy

This repository is a fork. `origin` is the fork (`tsg-ut/slack-patron`) and `upstream` is the original project (`tyage/slack-patron`).

**Always open pull requests against the `master` branch of the fork, `tsg-ut/slack-patron`. Never open a pull request against the upstream repository `tyage/slack-patron` under any circumstances.**

`gh` may resolve the default repository to the upstream, so always pass the target explicitly:

```sh
gh pr create --repo tsg-ut/slack-patron --base master
```

Verify the target before creating a PR, and if a command would create one against `tyage/slack-patron`, stop rather than proceeding.

## Overview

Slack Patron records all Slack messages into MongoDB and serves a web viewer for browsing/searching them. It also accepts Slack workspace export (backup) zips, and exposes read-only endpoints that mimic Slack's own `conversations.history` / `conversations.replies` APIs.

Ruby 3.4.4 (`.tool-versions`) + Sinatra backend, React/Redux frontend, MongoDB storage, Elasticsearch search.

## Services and data flow

Five containers defined in `docker-compose.yml`:

- **logger** (`logger/logger.rb`) — writes Slack events into MongoDB. Also listens on port 9293 when using the Events API.
- **viewer** (`viewer/viewer.rb`) — Sinatra app on port 9292. Serves the SPA, JSON endpoints, and the Slack-mimicking API.
- **connector** — [monstache](https://github.com/rwynn/monstache) tailing MongoDB's oplog into Elasticsearch. `connector/run.sh` also does one-time setup: it initiates the MongoDB replica set `rs0` and creates the `slack_logger.messages` ES index with a `kuromoji` analyzer for Japanese text and explicit `double` mappings for every nested `ts` field.
- **elasticsearch** / **mongo** — MongoDB runs as a single-node replica set (`--replSet rs0`), required for monstache oplog tailing.

Message flow: Slack → collector → `insert_message` → MongoDB `messages` → monstache → Elasticsearch. The viewer reads channel history from MongoDB directly but queries Elasticsearch (`http://elasticsearch:9200`, hardcoded in `viewer/viewer.rb`) for full-text search.

## Common commands

Development uses a devcontainer that mounts the repo at `/workspace` inside the `viewer` service:

```sh
export SLACK_PATRON_SLACK_TOKEN=...
devcontainer up --workspace-folder .devcontainer .

docker compose exec viewer bash
cd workspace
bundle install
./viewer/setup.sh                                # builds the frontend bundle (npm run build)
bundle exec ruby ./logger/logger.rb &             # start the logger
bundle exec rackup ./viewer/config.ru -o 0.0.0.0  # viewer at http://localhost:9292
```

Frontend (run from `viewer/`):

```sh
npm run build    # webpack production build → viewer/public/build/app.js
npm run watch    # webpack development watch
```

Import a Slack backup zip:

```sh
docker compose cp PATH_TO_BACKUP_FILE logger:/tmp/slack_backup.zip
docker compose exec logger bash -c "bundle exec ruby ./bin/import.rb /tmp/slack_backup.zip"
```

There are no tests in this repository (`npm test` is a stub). Verify changes by running the services.

## Configuration

`lib/config.rb` resolves each value from `./config.yml` first, then from an env var named `SLACK_PATRON_` + the uppercased key path joined by `_` (e.g. `database.uri` → `SLACK_PATRON_DATABASE_URI`). Ruby processes are expected to run with the repo root as cwd — `require './lib/...'` and `YAML.load_file('./config.yml')` are relative paths.

`bin/init.rb --token TOKEN` scaffolds a `config.yml`. Note its keys are strings for backward compatibility.

Setting `slack.use_events_api` truthy switches the collector from RTM to the Events API, which additionally requires `slack.team_id` (must start with `T`) and `slack.signing_secret`.

When `aws.access_key_id` / `aws.secret_access_key` are both present, the viewer presigns S3 URLs for message attachments (bucket `tsgbot-slack-files`, key = file id, `ap-northeast-1` — all hardcoded in `viewer/viewer.rb`).

## Backend structure

`lib/` is shared by all Ruby entrypoints (`logger/`, `viewer/`, `bin/`):

- `lib/db.rb` — the data layer. Requiring it creates the Mongo client, defines the top-level collection constants (`Messages`, `Users`, `Channels`, `Emojis`, `Ims`), and ensures indexes as a side effect. Everything else uses these globals rather than passing a client around.
- `lib/slack.rb` — global `Slack.configure` side effects plus `SlackPatron::SlackClient`, a thin pagination wrapper over the Web API.
- `lib/slack_logger.rb` — `SlackLogger` is the event sink the collectors call back into (`new_message`, `new_reaction`, `update_users`, …). `start` runs the collector in a thread while the main thread backfills channel history.
- `lib/collector/rtm.rb`, `lib/collector/events_api.rb` — interchangeable collectors; both call the same `SlackLogger` methods.
- `lib/slack_api.rb` + `lib/slack_api_helpers.rb` — the Slack-compatible API. Cursors are base64 of `"<before|after>:<ts>"`.
- `lib/slack_import.rb` — backup zip importer. Channels are matched by directory name against the `channels` collection; unknown channels are warned about and skipped.

### Message storage conventions

- `ts` is the unique key for messages (`Messages` has a unique index on `ts`), and `insert_message` upserts on it. `thread_ts` is also indexed.
- Reactions are stored **denormalized**: one `{name, user}` document per reacting user, so `$addToSet`/`$pull` can update a single reaction atomically. `denormalize_message` converts Slack's grouped form on write; `normalize_message` converts back to Slack's `{name, count, users}` form on read. Anything returning messages to a client must call `normalize_message(s)`.
- `insert_message` swallows all exceptions (`rescue` with an empty body) and unwraps `message_replied` / `message_changed` subtypes into the inner message. Both mean write failures are silent — keep that in mind when debugging missing messages.
- Messages with a file in `mode: 'hidden_by_limit'` have their `files` key dropped so stale placeholders don't overwrite real file data.
- Read paths filter with `{'$or' => [{hidden: {'$ne' => true}}, {subtype: 'tombstone'}]}` — deleted messages are kept as tombstones and still shown.
- `bin/migrations/denormalize-messages.rb` re-runs `insert_message` over every stored message; that is the pattern for schema migrations here.

Channel history backfill in `SlackLogger#start` sleeps 120s between channels because `conversations.history` is rate limited to 1 request per minute. It also materializes the channel cursor with `.to_a` first to avoid MongoDB cursor timeouts during the long loop.

## Frontend structure

`viewer/front/` — React 16 + Redux with `redux-thunk`, routed by `connected-react-router` over `history` v4. Webpack bundles to `viewer/public/build/app.js`; LESS is imported per-component and injected via `style-loader`.

- All server communication lives in `actions/SlackActions.js`; URLs are relative and cache-busted with a `?t=` timestamp. The SPA's base path comes from the `<base id="basename">` tag in `viewer/views/layout.erb`, so the app works when mounted under a sub-path.
- Routing is inside `components/MessagesSection.js` (`/search/:searchWord`, `/thread/:thread_ts`, `/:channel/:ts`, `/:channel`); the corresponding Sinatra routes all just render `index.erb`.
- Reducers in `reducers/` are one-concern-per-file, combined in `reducers/index.js`; action type strings live in `constants/SlackConstants.js`.

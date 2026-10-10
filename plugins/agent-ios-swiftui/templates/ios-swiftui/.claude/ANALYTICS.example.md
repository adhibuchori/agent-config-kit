# Analytics: Read API Access

> **List it in the CLAUDE.md "On-demand references" table; never `@`-import it.** An import loads
> the whole file into every session. This is a template for a self-hosted analytics instance
> reached over its REST export API: copy it to `.claude/ANALYTICS.md` and fill every
> `<placeholder>`.
>
> Delete this file and its table row if you have no analytics backend. An unfilled template is
> worse than an absent one: an agent will try to use it.

## What the app sends, and from where

Events leave from screen models and services, never from a view's `body` (a body runs on every
redraw). Name the client type the app uses and the one place it is configured:

- Client: `<type in Packages/AppCore>`
- Configured in: `<the composition root>`
- Consent: `<how the app asks, and where the answer is stored>`

Every data type the app collects is also declared in `App/PrivacyInfo.xcprivacy`
(`NSPrivacyCollectedDataTypes`), and in the App Store privacy answers.

## Base URL

```text
<analytics-host>/api
```

## Endpoints

| Endpoint | Purpose |
| --- | --- |
| `GET /<events-path>` | Raw events: filtering, pagination |
| `GET /<charts-path>` | Aggregated time series: breakdown, segmentation |

## Auth

Record the exact header shape: guessing `Authorization: Bearer` when the service wants two custom
headers costs an hour.

```text
<client-id-header>: <id>
<client-secret-header>: <secret>
```

Environment variables: `ANALYTICS_READ_CLIENT_ID`, `ANALYTICS_READ_CLIENT_SECRET`. They belong to
the person reading the data, never to the app: nothing that can read analytics ships in the bundle.

## Verified working example

Include one request that actually ran, with its actual response shape: `<method and path>` returns
`200` with `<shape>`; without the headers it returns `401`.

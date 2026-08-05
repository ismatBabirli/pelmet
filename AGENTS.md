<!-- Keep this file lean: pointers and rules, not prose. `CLAUDE.md` covers the
     codebase itself (architecture, commands, gotchas, product invariants). This
     file covers work that crosses repository boundaries. -->

# Agent guide

## Companion repository: the website

Pelmet's marketing and documentation site lives in a separate repository.

- Repo: `ismatBabirli/pelmet.xyz` (private)
- Live: https://pelmet.xyz
- Next.js, fully prerendered, self-hosted on Coolify. It redeploys itself on
  every merge to its `main`, so there is no manual publish step.

The site restates facts this repository owns: the current version, the
changelog, the feature list, the permission model, the telemetry schema, the
install commands, and the minimum macOS version. When those change here and not
there, the site starts telling users and search engines something untrue.

## Rule: every change here is also a website question

Before opening a PR in this repo, check the table. If a row applies, the site
needs a matching change and the two PRs ship together.

| Change here | What to update on the site |
|---|---|
| New release tagged `vX.Y.Z` | Usually nothing by hand: `lib/github.ts` reads the GitHub API hourly. Refresh its pinned `FALLBACK` release when it drifts more than a release or two behind. |
| `CHANGELOG.md` entry | `content/changelog.ts`. Transcribed by hand on purpose: release notes are prose that ships to an indexed page. |
| Feature added, changed, or removed | `content/comparisons.ts` rows, `app/features/*`, the "Not yet" list on `/features`, and `featureList` in `lib/schema.ts` |
| Permission model changes | `/privacy`, `/features/one-click`, `content/faq.ts`, and every "Works without ... permission" row in `content/comparisons.ts` |
| `docs/TELEMETRY.md` schema change | The field table in `app/privacy/page.tsx`, which mirrors that doc field for field |
| Minimum macOS version | `minMacOS` in `lib/site.ts`, which feeds both the pages and the structured data |
| Install command or distribution change | `brewCommand` in `lib/site.ts`, and `/download` |
| A roadmap item ships | The "Not yet" section of `/features`, plus any `content/comparisons.ts` row that currently says a rival has it and Pelmet does not |
| A claim about a competitor goes stale | `content/comparisons.ts`. Only claims checkable against that project's own docs, site, or repository. No invented benchmarks. |

If nothing applies, say so in one line in the PR description, so a reviewer can
tell it was considered rather than forgotten.

## Rule: cross-linked PRs, merged together

1. Branch and open the PR here as usual.
2. Branch `pelmet.xyz` and open the matching PR there.
3. Link them in both directions. Add a line to each PR description:
   `Pairs with ismatBabirli/pelmet.xyz#<n>` and, on the site PR,
   `Pairs with ismatBabirli/pelmet#<n>`.
4. Merge this repo's PR first, then the site's, so the site never documents a
   feature that is not yet on `main`. For a release, merge the site PR straight
   after the tag is pushed, so the changelog page is not left behind.
5. Do not merge only one of the pair. A half-merged pair is exactly the state
   this rule exists to prevent.

## Working in the site repo

Read its `README.md` first. Two things that catch people out:

- Every page must set `alternates.canonical`, carry exactly one `<h1>`, and be
  reachable from a hub page. `pnpm build` must show every route as static.
- `/llms.txt` and `/llms-full.txt` are generated from the same content modules
  as the pages, so editing content keeps them in sync automatically. Do not
  hand-edit their output.

## House style

The rules in `CLAUDE.md` section "Etiquette" apply to every repo touched on
Pelmet's behalf, including the site: no AI attribution in commits or PRs, and
no em-dashes in prose you add.

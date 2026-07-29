# Releasing

## Where this repo lives

| | |
|---|---|
| **Authoring** | `git.arolo.net/prelude-public/prelude-collector-playground` (private) |
| **Publishing** | `github.com/Arolo-Solutions/prelude-collector-playground` (public) — *not wired up yet* |

Work happens on GitLab; GitHub is a **push mirror**. `git.arolo.net` is not publicly resolvable, so
GitHub is the only surface a customer can read — including the **Playground** link the collector
renders on every vendor-profile row. Treat the mirror as load-bearing, not decorative.

The group is named `prelude-public` because its content is *destined* for public release. The GitLab
group and project themselves are deliberately **private**.

> Not to be confused with `prelude/prelude-collector-playground` — a different, unrelated project used
> as the test target of the collector's `git-sync` feature.

## Versioning

Tag `vX.Y.Z` matching **the collector version the content was verified against**, so
"which playground matches my collector" has an answer.

This matters more than it looks. The vendored `prelude-mcp-companion` skill once sat four weeks stale
and documented the pre-1.1.3 *declared* mapping key after the collector had moved to a *derived* key —
silently wrong advice. Pinning the tag to a collector version makes that kind of drift visible.

## Cutting a release

1. **Refresh the vendored skills** and commit any delta:

   ```bash
   ./scripts/sync-skills.sh
   ```

   Skills are copies. Their sources of truth are `prelude-claude/skills/prelude-collector-api` and
   `prelude-mcp/skills/prelude-mcp-companion`; each of those repos runs a CI job that fails while its
   copy here differs. **Fix skills upstream, then sync** — never edit `skills/` directly.

2. **Re-verify every artifact imports** against a collector at the target version:

   ```bash
   TOKEN=$(cd /path/to/prelude-collector && go run . user token -u admin -d 'playground-verify' | tail -1)

   for model in vendors/*/models/*.json shared/models/*.json; do
     code=$(curl -ks -o /dev/null -w '%{http_code}' -X POST \
       -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
       --data-binary "@$model" https://127.0.0.1:4030/api/v1/models/0/import)
     echo "$code  $model"
   done

   for profile in vendors/*/profile.json; do
     code=$(curl -ks -o /dev/null -w '%{http_code}' -X POST \
       -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
       --data-binary "@$profile" "https://127.0.0.1:4030/api/v1/vendor-profiles/import?overwrite=true")
     echo "$code  $profile"
   done
   ```

   Every line must be 2xx. Spot-check one imported model in the UI for fields **and** mappings — a
   model can import with its fields and silently lose mappings if the export format has moved on.

3. **Bump the compatibility line** in `README.md` ("Verified against Prelude Collector vX.Y.Z") and
   each vendor README's *Verified against* section if the lab changed.

4. **Check nothing internal leaked** — the content is destined for a public repo:

   ```bash
   grep -rn -E 'arolo\.net|172\.31\.|10\.0\.0\.|arolo123|prelude-collector\.test|password' \
     --exclude-dir=.git . || echo clean
   ```

   Hits inside `skills/` are usually legitimate (documented API examples); hits in `vendors/`,
   `shared/` or the READMEs are not.

5. **Tag and push** on GitLab:

   ```bash
   git tag vX.Y.Z && git push origin main --follow-tags
   ```

6. **Publish on GitHub** *(once the mirror is wired)*: the mirror carries the commit and tag; create a
   GitHub Release on the tag with short notes and attach the two `.skill` bundles
   (`prelude-collector-api.skill`, `prelude-mcp-companion.skill`) so the skills install without a
   clone.

7. **Cross-link the docs** — add or refresh the pointer from the customer portal
   (`arolo-customer-portal`) to this repo. The link currently only runs one way: this repo's README
   deep-links the portal's MCP install page, not the reverse.

Release notes here are a short hand-written section. The `release-prelude` skill is for *collector*
release notes (portal + wiki, tag-to-tag commit gathering) — don't route this repo through it.

## Still open

- **`LICENSE`** — not chosen yet, and required before the repo goes public. This would be Arolo's
  first public repo, so the choice sets a precedent (Apache-2.0 vs MIT vs CC0).
- **The GitHub mirror itself** — repo not created, mirror not configured.
- **The collector's shipped seed URLs** — the 7 profiles in
  `collector/collection/vendorprofiles/seeds/*.json` still point at a non-existent
  `arolo/prelude-collector-playground` project. They must be repointed to the GitHub URLs
  (`…/tree/main/vendors/<netos>`) once the mirror exists; until then the in-app Playground link is
  dead. The `profile.json` files *in this repo* already carry the correct final URLs.
- **Per-vendor content** — 7 of 8 vendor directories ship a profile and README but no models.

---
name: coupled-tags
description: Add COUPLED:<key>. comments linking values or code that must change together but can't share a single source of truth. Before editing anything tagged COUPLED:, update every site.
argument-hint: <this> with <that> [as <key>]
---

# COUPLED tags

Some things must change together but cannot share a single source of truth: a runtime version pinned in several files, size or timeout limits that must stay ordered across a proxy and an app, a URL registered in an external console, a block of code deliberately duplicated. Every site gets a greppable tag, so whoever changes one finds the others.

## Format

```
<value or code>    <comment> COUPLED:<key>. <relation from this site's point of view>
```

- `<key>`: lowercase `[a-z0-9-]`. One key per group, so `grep -rn 'COUPLED:<key>\.'` shows every site.
- `.` terminates the key, which makes that grep exact.
- `<relation>`: `<op> <component>:<thing>`. Always write one, even if it is only `=`. A component is a short name for the file or system holding the other site (`nginx`, `docker`, `ci`, `app`, `google-console`).
- Use the file's own comment syntax. Placement:
  - Single-line value or statement: same line, as a trailing comment.
  - Multi-line block: its own comment line directly above.
  - Whole function: in its docblock, so the tag moves with the function and shows in IDE hovers. No docblock: the line above.
  - Line cannot take a trailing comment: the line above. Examples: Dockerfiles and many `.env` parsers only allow whole-line comments, and in a Makefile the spaces before an inline `#` become part of the value.
- Code: say what must stay equivalent.
- Formats without comments (JSON, `.nvmrc`): tag the other sites and name the comment-less file in their relation.
- Markdown: plain visible text.
- Keep any existing comment: tag first, then the existing text.

## Choosing the key

Name the invariant the group protects, not the technology or file it lives in: `request-timeout-chain`, not `nginx-timeouts`; `python-version`, not `versions`. Test it both ways:
- If an unrelated setting could plausibly carry the key, it is too vague.
- If a site that belongs would look out of place carrying it, it is too narrow.

If the user supplied a key (`as <key>`), use it. Otherwise propose one or two and wait for the user to choose before tagging anything.

## Examples

```dockerfile
# COUPLED:python-version. = ci:python-version, pyproject:requires-python
FROM python:3.12-slim
```
```yaml
python-version: "3.12"         # COUPLED:python-version. = docker:FROM tag, pyproject:requires-python
```
```nginx
client_max_body_size 10m;      # COUPLED:upload-size-limit. >= app:MAX_UPLOAD_MB
```
```python
MAX_UPLOAD_MB = 8              # COUPLED:upload-size-limit. <= nginx:client_max_body_size
```
```js
server.keepAliveTimeout = 65_000;  // COUPLED:keepalive-timeout. > aws-alb:idle timeout (docs/external/aws-alb.md)
```
```js
// COUPLED:password-rules. same rules as app:PasswordValidator::validate()
function validatePassword(value) { ... }
```

## Relation kinds

| Kind | Notation |
|---|---|
| Identical | `= ci:python-version` |
| Same meaning, different units/spelling | `= php:post_max_size (M vs m)` |
| Ordering | `<`, `<=`, `>`, `>=` |
| Formula | `app:workers * app:memory_per_worker <= k8s:memory limit * 0.8` |
| Set membership | `⊇ app:routes` |
| Equivalent behaviour (code) | `same output as app:Logger::write()` |
| External | `= google-console:redirect URIs (docs/external/google-oauth.md)` |
| Intentional difference | `!= prod:session.cookie_domain (deliberate)` |

## External systems

Nobody can grep the far end of an external coupling, so the repo needs a record of it. Keep the **current** configuration of each external system in `docs/external/<service>.md`: what is set, where, and for which environment. Put the same `COUPLED:<key>.` tag beside each value in that doc. Create or update it whenever an external coupling is added or changed. Leave visible TODOs for values you cannot see.

## Adding a coupling (`/coupled-tags $ARGUMENTS`)

1. Settle the key (see above).
2. Find every site, not only the ones named. Grep for the literal value and related names across dev and prod configs, build files, app code and docs.
3. Reuse an existing key if this group already has one (`grep -rn 'COUPLED:'`).
4. Tag each site with the relation from its own perspective.
5. Check that the relations hold now. Report any violations to the user; never silently change values.
6. For external sites, create or update `docs/external/<service>.md`.
7. Run `sh <directory containing this file>/scripts/coupled-tags-lint.sh` from the repo root and fix what it reports.
8. Report the key and the tagged sites.

## Changing a tagged value or block

1. Run `grep -rn 'COUPLED:<key>\.'` and read every site.
2. Change all the sites together, so every relation still holds.
3. For external sites, tell the user what to change outside the repo, and update the external doc.

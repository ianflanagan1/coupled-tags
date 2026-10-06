# COUPLED tags

A comment convention for code and values that must change together but can't share a single source of truth. Each place gets a greppable tag, so whoever changes one can run `grep -rn 'COUPLED:<key>\.'` and find the others.

It ships with a lint script and a Claude Code skill.

## Why

Configuration is spread across tools that can't read each other: proxies, app servers, CI, Dockerfiles and external consoles. A plain "keep in sync with X" comment is easy to miss and can't be searched for reliably. A tag can.

Prefer to use a single source of truth whenever possible: environment variables, templating, generated files or a shared module. Use a tag when that costs more than it saves, or until a refactor makes it possible.

## Examples

### A duplicated function

E.g. Legacy code awaiting a refactor.

```java
// src/main/java/com/example/billing/Invoice.java
/**
 * COUPLED:vat-calculation. same result as checkout:Cart.calculateVat()
 */
private int calculateVat(int netPence) { ... }
```
```java
// src/main/java/com/example/checkout/Cart.java
/**
 * COUPLED:vat-calculation. same result as billing:Invoice.calculateVat()
 */
private int calculateVat(int netPence) { ... }
```

---

### A runtime version pinned in several files

```toml
# pyproject.toml
requires-python = ">=3.12"     # COUPLED:python-version. = ci:python-version, docker:FROM tag
```
```yaml
# .github/workflows/ci.yml
python-version: "3.12"         # COUPLED:python-version. = pyproject:requires-python, docker:FROM tag
```
```dockerfile
# Dockerfile
# COUPLED:python-version. = pyproject:requires-python, ci:python-version
FROM python:3.12-slim
```

---

### An upload limit that must be larger at the proxy than in the app

```nginx
# nginx/default.conf
client_max_body_size 10m;      # COUPLED:upload-size-limit. >= app:MAX_UPLOAD_MB
```
```python
# app/settings.py
MAX_UPLOAD_MB = 8              # COUPLED:upload-size-limit. <= nginx:client_max_body_size
```

---

### A load-balancer idle timeout that must be shorter than the app's keep-alive timeout

```js
// server.js
server.keepAliveTimeout = 65_000;  // COUPLED:keepalive-timeout. > aws-alb:idle timeout (docs/external/aws-alb.md)
```
```markdown
<!-- docs/external/aws-alb.md -->
Idle timeout: 60 s (EC2 console > Load balancers > prod-alb > Attributes). COUPLED:keepalive-timeout. < app:server.keepAliveTimeout
```

---

### An OAuth redirect URI registered in a provider's console

```python
# app/auth.py
REDIRECT_URI = "https://example.com/auth/callback"  # COUPLED:oauth-redirect-uri. = google-console:redirect URIs (docs/external/google-oauth.md)
```
```markdown
<!-- docs/external/google-oauth.md -->
Authorised redirect URIs: `https://example.com/auth/callback`. COUPLED:oauth-redirect-uri. = app:REDIRECT_URI
```


## Format

```
<value or code>    <comment> COUPLED:<key>. <relation from this site's point of view>
```

- **Key:** lowercase letters, digits and `-`. A key names a *group*, so one grep finds every site in it.
- **`.`** ends the key. That makes `grep 'COUPLED:<key>\.'` an exact match, so `upload-size-limit` doesn't also match `upload-size-limit-v2`.
- **Relation:** describes how this site relates to the others: `<op> <component>:<thing>`. The component is a short name for the file or system holding the other site. The relation is optional, but recommended: it says what must stay true, which is what a tag adds over "keep in sync". Even `=` is worth writing.
- **Placement:** use the file's own comment syntax.
  - A single-line value or statement: on the same line.
  - A multi-line block: on its own line directly above.
  - A whole function: in its docblock, so the tag moves with the function and shows in IDE hovers.
  - A line that can't take a trailing comment: directly above. For example, Dockerfiles only allow whole-line comments, and in a Makefile `VAR := x  # note` makes the spaces part of the value.

### Choosing a key

Name the invariant the group protects, not where it lives: `request-timeout-chain`, not `nginx-timeouts`. If an unrelated setting could plausibly carry the key, it's too vague.

### Relations

| Kind | Example |
|---|---|
| Identical | `= ci:python-version` |
| Same meaning, different units | `= php:post_max_size (M vs m)` |
| Ordering | `< app:keepAliveTimeout` |
| Formula | `app:workers * app:memory_per_worker <= k8s:memory limit * 0.8` |
| Set membership | `⊇ app:routes` |
| Equivalent behaviour (code) | `same output as app:Logger::write()` |
| External | `= google-console:redirect URIs (docs/external/google-oauth.md)` |
| Intentional difference | `!= prod:cookie_domain (deliberate)` |

### External systems

When the other end lives outside the repo (a cloud console, DNS, a provider's dashboard), describe its **current** configuration in `docs/external/<service>.md`, and put the same tag next to each value. The grep then finds the doc, and the doc says what to change and where.

## Lint

`skills/coupled-tags/scripts/coupled-tags-lint.sh` is POSIX `sh` and runs anywhere. It reports:

- **malformed tags:** the key has uppercase letters or underscores, or is missing the `.`
- **orphan keys:** the key appears only once, which usually means the other end was deleted

```sh
sh path/to/coupled-tags-lint.sh            # check the current directory
sh path/to/coupled-tags-lint.sh -l         # also list every key and its sites
sh path/to/coupled-tags-lint.sh -x docs/   # exclude a path prefix (repeatable)
```

In a git work tree it scans tracked files plus untracked files that aren't ignored. Elsewhere it uses `grep -r`, skipping `.git`, `node_modules` and `vendor`. The skill directory containing the script is always excluded, so a copy vendored into a repo doesn't flag its example tags. It exits with 0 when clean, 1 when it finds problems, and 2 on a usage error.

It does **not** check that changes to a key touch every site. Diff-aware enforcement in the style of Google's `LINT.IfChange` is out of scope.

## Claude Code

The `coupled-tags` skill teaches Claude the convention:

- **Adding:** `/coupled-tags <this> with <that> [as <key>]`. Claude finds every site, tags each one, checks the relations hold and runs the lint script. If you don't give a key, it proposes one and waits for your choice.
- **Honouring:** before editing anything tagged `COUPLED:`, Claude greps the key and updates every site.

Install it as a plugin:

```
/plugin marketplace add ianflanagan1/coupled-tags
/plugin install coupled-tags@coupled-tags
```

Plugin skills are namespaced, so it's invoked as `/coupled-tags:coupled-tags`.

You can vendor it instead, so collaborators get it with the repo: copy `skills/coupled-tags/` to `.claude/skills/coupled-tags/` in your project, and it's invoked as `/coupled-tags`. Don't install it both ways at once, or Claude will see the skill twice.

Recommended line for your project's `CLAUDE.md`. A skill's description doesn't guarantee Claude loads it just because it's editing a tagged line; this does:

```
Before changing anything tagged `COUPLED:<key>.`, grep the key and update every site (see the coupled-tags skill).
```

## Other agents

The convention and the lint script don't depend on any agent. `skills/coupled-tags/SKILL.md` uses the [Agent Skills](https://agentskills.io) format, so other agents that support skills can load it.

- **Agents that support skills:** copy `skills/coupled-tags/` into your agent's skills directory (see its docs for the location). Keep the folder intact, so `scripts/coupled-tags-lint.sh` stays alongside `SKILL.md`. Slash-command arguments may behave differently, so just ask the agent in plain language, for example "couple the nginx upload limit with the app's `MAX_UPLOAD_MB`".
- **Any agent:** add this to your project's `AGENTS.md` (or the agent's equivalent instructions file):

  ```
  Code and values that must change together are tagged `COUPLED:<key>. <relation>` in comments.
  Before changing anything tagged `COUPLED:<key>.`, run `grep -rn 'COUPLED:<key>\.'`, read every site,
  and update them together so every relation still holds. Never silently change a value to satisfy a relation; report violations.
  ```

- **CI:** run `sh path/to/coupled-tags-lint.sh` as a step to catch malformed tags and orphan keys whoever made the edit.

## Prior art

- Google's `LINT.IfChange` / `LINT.ThenChange`, enforced at code review
- "Keep in sync with ..." comments

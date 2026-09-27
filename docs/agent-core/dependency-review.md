# dependency-review

Workflow · agent-core · `.github/workflows/dependency-review.yml` · installed by setup · runs on every pull request · no secrets

## What it does

`.github/workflows/dependency-review.yml` fails a pull request that adds or raises a dependency with a known high or critical vulnerability, in runtime and development dependencies alike. It compares the dependency graph of the base and head commits over the API: no checkout, no install, no project code.

It stands in for Dependabot: nothing opens update pull requests on a timer, and every dependency change is checked when a pull request makes it.

## When to reach for it

Setup installs it; it runs by itself on every pull request:

```text
/agent-core:setup
```

**Not for:** a private repository without GitHub Code Security; the job skips there until you set the repository variable `CODE_SECURITY` to `true`.

## Prerequisites

- GitHub's dependency graph must recognise your lockfile (Insights, Dependency graph).

## Common questions

**Can it enforce licences?**
Yes: uncomment the `deny-licenses` line in the file and edit the list. It is off by default because which licences are acceptable is your project's decision.

## It's working if

- Each pull request shows a **Dependency Review** check, and one that adds a package with a high-severity advisory fails it.

## Where it fits

Next to [codeql](codeql.md) and [workflows-lint](workflows-lint.md); see
[CI/CD at a glance](../../README.md#cicd-at-a-glance).

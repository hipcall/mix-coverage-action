# Mix Coverage

Parse `mix test.coverage` output, post or update a sticky PR comment, and enforce total and per-module coverage thresholds.

Supports both the pre-1.20 table format (plain `Percentage | Module`) and the markdown-pipe format introduced in Elixir 1.20. Useful for hex packages that test across multiple Elixir versions in the same workflow.

## Usage

Minimal — post a sticky PR comment after your test job runs:

```yaml
- uses: hipcall/mix-coverage-action@v1
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

Typical — enforce total and per-module thresholds:

```yaml
- name: Tests & Coverage
  run: |
    mix test --cover --export-coverage default
    mix test.coverage

- uses: hipcall/mix-coverage-action@v1
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    minimum-coverage: 80
    minimum-module-coverage: 70
```

Also show a Changed files section in the comment (informational — helps reviewers focus):

```yaml
- uses: hipcall/mix-coverage-action@v1
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    minimum-coverage: 80
    include-changed-files: true
```

Parse a pre-captured log instead of running a command:

```yaml
- uses: hipcall/mix-coverage-action@v1
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    coverage-file: ./cover/summary.txt
```

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `github-token` | yes | — | Token used to post the PR comment. `${{ secrets.GITHUB_TOKEN }}` is sufficient. |
| `coverage-command` | no | `mix test.coverage` | Command producing a `mix test --cover` or `mix test.coverage` table on stdout. Ignored when `coverage-file` is set. |
| `coverage-file` | no | `""` | Path to a pre-captured coverage log. When set, `coverage-command` is skipped. |
| `minimum-coverage` | no | `0` | Fail the step when total coverage is below this percentage. `0` disables. |
| `minimum-module-coverage` | no | `0` | Fail the step when any reported module is below this percentage. Applies to every module. `0` disables. |
| `include-changed-files` | no | `false` | When true on a PR, add a Changed files section to the comment listing modules mapped from files modified in the PR. Informational only — no gate. |
| `comment` | no | `sticky` | PR comment behavior: `sticky` (create/update marked comment), `new`, or `off`. |
| `working-directory` | no | `.` | Directory in which to run `coverage-command`. |

## Outputs

| Name | Description |
|------|-------------|
| `total-coverage` | Total coverage percentage as a string, e.g. `85.70`. |
| `failed-modules` | JSON array of modules below the per-module threshold after any changed-files filter. |

## How it works

1. Runs `coverage-command` and captures stdout (exit code is ignored — `mix test.coverage` exits non-zero when its own `:threshold` is unmet; this action is the single authoritative gate).
2. Parses the 1.20 markdown-pipe table: `| Percentage | Module |` header, per-module rows, and the trailing `Total` row.
3. On pull requests, posts or updates a comment marked with an HTML comment so repeat runs update in place.
4. Applies threshold gates and exits non-zero if any fail.

Module-to-file mapping for `include-changed-files` uses the Elixir naming convention (`Macro.underscore` of the module name) against the PR's changed file list. Edge cases (multiple modules per file, nested modules split across files) may produce conservative matches.

## Elixir configuration tip

Because this action is the authoritative gate, disable `mix`'s built-in threshold by setting it to `0` in your project's `mix.exs`:

```elixir
def project do
  [
    # ...
    test_coverage: [summary: [threshold: 0]]
  ]
end
```

## License

[MIT](LICENSE) © Hipcall

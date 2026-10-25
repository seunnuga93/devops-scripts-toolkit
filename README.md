# devops-scripts-toolkit

![ci](https://github.com/seunnuga93/devops-scripts-toolkit/actions/workflows/ci.yml/badge.svg)

Everyday ops utilities, written to be safe to run unattended from cron or CI. Every script
validates its input, uses exit codes you can alert on, and is covered by tests that run on
Linux and macOS.

## Bash (`bin/`)

| Script | What it does |
| --- | --- |
| `cert-expiry-check.sh` | Warns when TLS certs (live hosts or PEM files) expire within N days. Uses `openssl -checkend`, so there are no GNU/BSD `date` differences. |
| `disk-usage-alert.sh` | Lists filesystems over a usage threshold, with optional Slack webhook. |
| `log-cleanup.sh` | Gzips logs older than N days and deletes ones older than M days. `-n` for dry run. |
| `backup-to-azure-blob.sh` | Tars a directory, uploads it to Blob Storage using AAD auth (no account keys), and prunes old backups. |

```bash
bin/cert-expiry-check.sh -d 21 github.com example.com:443
bin/disk-usage-alert.sh -t 80 -w "$SLACK_WEBHOOK_URL"
bin/log-cleanup.sh -c 7 -r 30 -n /var/log/myapp
bin/backup-to-azure-blob.sh -a mystorageacct -c backups -k 14 /srv/data
```

Example cron entry:

```cron
0 7 * * *  /opt/toolkit/bin/cert-expiry-check.sh -d 21 api.example.com || /opt/toolkit/bin/notify.sh "cert expiring"
```

## Python (`python/devops_toolkit/`)

Standard library only, installable as CLI commands:

```bash
pip install .
```

**`healthcheck`**: checks many HTTP endpoints concurrently, with a latency budget and JSON output for pipelines.

```
$ healthcheck https://github.com https://example.com/missing --max-latency 800
URL                          STATE  CODE  LATENCY  DETAIL
https://github.com           UP     200   142ms
https://example.com/missing  DOWN   404   98ms     HTTP 404
```

**`azure-cost-report`**: spend for a subscription grouped by resource group, service or region,
pulled from the Cost Management API using your `az login` token.

```
$ azure-cost-report --subscription $SUB --days 30 --top 3
NAME            COST  SHARE
rg-aks        412.18   61.2%
rg-data       150.40   22.3%
rg-web         80.02   11.9%
(2 more)       31.10
TOTAL         673.70  GBP
```

## Tests

```bash
shellcheck bin/*.sh
bats tests/bats                    # 12 tests
pip install -e . pytest && pytest  # 11 tests
```

CI runs the shell tests on Ubuntu and macOS, and the Python tests on 3.9 and 3.12.

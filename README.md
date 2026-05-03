rbackup
=======

A Perl-based backup tool that uses rsync over SSH to back up multiple remote hosts.
Each backup run creates a full mirror in `current/` and stores changed files in a
timestamped `differential/` directory, giving you a full backup plus incremental history.

## Features

- Multiple remote hosts, each with individual include/exclude paths
- Differential (incremental) backups with one directory per run
- Optional `ipaddr` per host to connect by IP while keeping a friendly hostname for storage and logging
- INI-style config file — no editing of the script required
- Backup statistics: size, file count, revision count, newest file timestamp
- Dry-run mode for testing without making changes

## Requirements

- Perl 5
- rsync
- SSH access to each remote host (key-based authentication recommended)

## Usage

```
rbackup.pl [options]

  -r, --run       Run backup
  -s, --stats     Show backup statistics per host
  -H, --hosts     List configured hosts with include/exclude paths
  -t, --test      Dry run — show what would be done without executing
  -v, --verbose   Print log output to stdout as well as the log file
  -c, --config    Path to config file (default: rbackup.conf next to the script)
  -h, --help      Print help
```

## Config file

Copy `rbackup.conf.dist` to `rbackup.conf` and edit it. The config has a `[global]`
section for shared settings and one section per host named by hostname.

```ini
[global]
backup_dir      = /data/backup
logdir          = /var/log/rbackup
ssh_key         =
ssh_known_hosts =
options         = -v --info=BACKUP,COPY,DEL -a -R -z --delete --force --ignore-errors

[web01.example.com]
user    = root
include = /etc, /home, /var/www
exclude = /tmp/

[db01.example.com]
user    = backup
ipaddr  = 192.168.1.50
include = /etc, /var/lib/mysql
exclude = /tmp/
```

- `include` and `exclude` are comma-separated; spaces around commas are ignored
- `ipaddr` is optional — if set it is used for the SSH/rsync connection instead of the section name

## Backup directory structure

```
/data/backup/
  web01.example.com/
    current/          # full mirror of the latest backup
    differential/
      2026-05-01-01-00/   # files that changed in that run
      2026-05-02-01-00/
```

## Logging

Each backup run appends to `$logdir/rbackup.log`. A per-host log for each run is
written to `$logdir/<hostname>-<timestamp>.log`.

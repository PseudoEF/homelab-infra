# Moto G60 homelab

A small, self-hosted edge for a portfolio and public demos, running entirely on
an Android phone with Termux. No VPS, no managed database, no third-party
analytics.

```text
Internet
  └── Cloudflare edge
        └── cloudflared tunnel (phone)
              ├── gordaya.pp.ua ────────► :3000  real Next.js salon
              └── :8080 nginx
                    ├── pseudoef.pp.ua ──► static portfolio hub
                    ├── crm.pseudoef.pp.ua ► static client-only CRM
                    ├── sim.pseudoef.pp.ua ► static scripted simulator
                    ├── panel.pseudoef.pp.ua ► :8082 read-only panel demo
                    └── salon.pseudoef.pp.ua ► :3001 resettable salon demo
```

The real admin panel and the real salon database are **not** on the tunnel.
The public demos use synthetic data and separate processes.

## Components

- `deploy.sh` — tar-over-SSH deployment. The phone has no `rsync`.
- `nginx/nginx.conf` — host routing, default-404, rate limits, static roots,
  reverse proxies for the demos.
- `cloudflared/config.yml.example` — tunnel ingress; copy and fill the tunnel ID.
- `termux/boot-00-srv` — Termux:Boot startup and watchdog installation.
- `termux/watchdog.sh` — recovers `runsvdir` after Android kills it.
- `docs/dns.md` — the correct Cloudflare records and the zone/certificate trap.

## Deployment

```bash
# Portfolio hub; keeps crm/ and sim/ intact
./deploy.sh hub ~/projects/portfolio

# Static sub-apps
./deploy.sh static ~/projects/techsupport-crm/dist crm
./deploy.sh static ~/projects/support-rage-sim/demo sim

# App source; secrets and data are excluded
./deploy.sh app ~/projects/gordaya-demo gordaya-demo
```

The script excludes `.env*`, `*.db*`, `auth.json`, `data/`, `logs/`,
`node_modules/`, `.next/` and `.git/` from app ships. It never uses `rsync
--delete` on an application directory. Static targets are extracted to a
staging directory and swapped.

After an app deploy, build and restart explicitly:

```bash
ssh -p 8022 u0_a281@192.168.88.15
export SVDIR=$PREFIX/var/service
cd ~/apps/gordaya-demo
set -a; . demo/.env.demo; set +a
npm ci && npm run build
sv restart gordaya-demo
```

## Supervision

Services are runit directories under `$PREFIX/var/service`:

```text
sshd  nginx  panel  gordaya  cloudflared  panel-demo  gordaya-demo
```

Useful commands:

```bash
export SVDIR=$PREFIX/var/service
sv status sshd nginx panel gordaya cloudflared panel-demo gordaya-demo
sv restart nginx
sv down redis
```

`postgres`, `redis` and `ssh-agent` are intentionally disabled with `down`
files. They are not used and Android's phantom-process limit is tight.

`boot-00-srv` starts the supervised services, waits briefly for `runsvdir`,
and installs two persisted Termux jobs:

- `1001` — watchdog every 15 minutes;
- `1002` — Gordaya demo reset every 6 hours.

## Edge and security

- nginx listens on `8080`; unknown `Host` values return 404.
- The real panel listens on the LAN at `8081`; it is not in the tunnel.
- The public panel demo is `127.0.0.1:8082`, GET-only, synthetic, with write
  endpoints returning 403.
- The salon demo is `127.0.0.1:3001`, with a separate `data/demo.db`, a runtime
  path guard, fictional seed data and a 6-hour reset.
- Login and demo hosts have nginx rate limits; demo request bodies are capped.
- The static sites have a strict CSP, no external fonts or images; Cloudflare's
  own analytics beacon is allowed explicitly.
- No credentials are committed. `cert.pem`, tunnel credentials, `.env` files
  and SQLite databases are gitignored.

## Recovery

If Android kills `runsvdir` but leaves orphan services, the watchdog kills the
known orphans, waits for the ports to free, starts `runsvdir`, and brings the
services up. Check `~/logs/watchdog.log`.

If the tunnel is down:

```bash
sv status cloudflared
tail -50 ~/logs/cloudflared.txt
cloudflared tunnel info moto-homelab
```

If a static deploy is bad, re-run `deploy.sh hub`/`static`; the previous target
is swapped out only after the new staging copy extracts successfully.

## Constraints

- One phone, one nginx worker, ~23–27 steady processes.
- No container isolation; every public process runs as the same Termux UID.
  The separation is process-level and application-level, not a security kernel.
- The tunnel certificate currently belongs to the `gordaya.pp.ua` zone, so
  `cloudflared tunnel route dns` cannot create records in the `pseudoef.pp.ua`
  zone. Add those records in the correct zone; see `docs/dns.md`.
- No license has been granted yet.

# DNS for `pseudoef.pp.ua`

The tunnel is connected and the Cloudflare zone for `pseudoef.pp.ua` is active,
but the zone is **not the same zone as the tunnel certificate** (`gordaya.pp.ua`).
Because of that, this command is wrong for the portfolio hostnames:

```bash
cloudflared tunnel route dns <tunnel> crm.pseudoef.pp.ua
```

It creates `crm.pseudoef.pp.ua.gordaya.pp.ua`, because the certificate only knows
the `gordaya.pp.ua` zone. Those records route to the tunnel but do not match any
ingress hostname, so they return the tunnel's default 404.

## Correct records

Add these in the Cloudflare dashboard for the **`pseudoef.pp.ua`** zone, or with
an API token that has `Zone.DNS Edit` on that zone. The tunnel target is
`<TUNNEL_ID>.cfargotunnel.com`:

| Type | Name | Target | Proxy |
| --- | --- | --- | --- |
| CNAME | `@` | `<TUNNEL_ID>.cfargotunnel.com` | Proxied |
| CNAME | `www` | `<TUNNEL_ID>.cfargotunnel.com` | Proxied |
| CNAME | `crm` | `<TUNNEL_ID>.cfargotunnel.com` | Proxied |
| CNAME | `sim` | `<TUNNEL_ID>.cfargotunnel.com` | Proxied |
| CNAME | `panel` | `<TUNNEL_ID>.cfargotunnel.com` | Proxied |
| CNAME | `salon` | `<TUNNEL_ID>.cfargotunnel.com` | Proxied |

Get the current tunnel ID on the phone:

```bash
cloudflared tunnel list
cloudflared tunnel info moto-homelab
```

For the apex, Cloudflare accepts a proxied CNAME at the zone root and flattens it.
Do not create an A record unless you intentionally bypass the tunnel.

## Delete the wrong records

In the **`gordaya.pp.ua`** zone, delete these CNAMEs if present:

```text
pseudoef.pp.ua
www.pseudoef.pp.ua
crm.pseudoef.pp.ua
sim.pseudoef.pp.ua
panel.pseudoef.pp.ua
salon.pseudoef.pp.ua
```

Their full DNS names are `<name>.gordaya.pp.ua`, for example
`crm.pseudoef.pp.ua.gordaya.pp.ua`. They are harmless because the tunnel returns
404 for them, but they are confusing and should not stay in the salon zone.

## Verify

```bash
# Nameservers / zone
curl -sS -H 'Accept: application/dns-json' \
  'https://cloudflare-dns.com/dns-query?name=pseudoef.pp.ua&type=NS'

# Public hosts
for h in pseudoef.pp.ua www.pseudoef.pp.ua crm.pseudoef.pp.ua \
         sim.pseudoef.pp.ua panel.pseudoef.pp.ua salon.pseudoef.pp.ua; do
  printf '%s ' "$h"
  curl -sS -o /dev/null -w '%{http_code}\n' "https://$h/"
done
```

All six should return `200` (the panel and salon through nginx). Unknown hosts
must not fall through to the real salon.

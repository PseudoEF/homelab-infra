# DNS for `pseudoef.pp.ua`

> Status: verified on 2026-10-26. All six proxied CNAMEs are live and return
> `200`; the six wrong records in the salon zone were deleted. Tunnel ID:
> `dc30f777-c6b2-4913-9a24-f257c5ee9fdd`.

The tunnel is connected and the Cloudflare zone for `pseudoef.pp.ua` is active,
but it is **not the same zone as the tunnel certificate** (`gordaya.pp.ua`).
That is why this command was wrong for the portfolio hostnames:

```bash
cloudflared tunnel route dns <tunnel> crm.pseudoef.pp.ua
```

It created `crm.pseudoef.pp.ua.gordaya.pp.ua`, because the certificate only knows
the `gordaya.pp.ua` zone. Those records routed to the tunnel but did not match
any ingress hostname, so they returned the tunnel's default 404.

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

In the **`gordaya.pp.ua`** zone, these CNAMEs were deleted on 2026-10-26:

```text
pseudoef.pp.ua
www.pseudoef.pp.ua
crm.pseudoef.pp.ua
sim.pseudoef.pp.ua
panel.pseudoef.pp.ua
salon.pseudoef.pp.ua
```

Their full DNS names were `<name>.gordaya.pp.ua`, for example
`crm.pseudoef.pp.ua.gordaya.pp.ua`. They were harmless because the tunnel
returned 404 for them, but they were confusing and did not belong in the salon
zone.

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

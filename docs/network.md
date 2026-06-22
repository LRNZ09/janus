# Network, firewall & DNS

## Assumptions (adjust for your environment)

| Item | Value | Notes |
| --- | --- | --- |
| Router model | ASUS GT-AX6000 | arm64 / aarch64; quad-core |
| Router firmware | Asuswrt-Merlin + Entware | stock firmware can't run Tailscale |
| LAN subnet | `192.168.50.0/24` | RFC 1918 |
| Default gateway (router) | `192.168.50.1` | also the Tailscale subnet router & exit node |
| Traefik | `192.168.50.254` | macvlan IP on the NAS; serves `:443` |
| AdGuard Home | `192.168.50.254` | shares Traefik's netns / address; `:53` |
| NAS / DSM | its own LAN IP in the /24 | reachable over the tailnet via the advertised route |
| Service domain | `*.admin.lorenzopieri.dev` | public domain; Traefik certs via Cloudflare DNS-01 |

If your LAN uses a different subnet, change it in **both** the
`--advertise-routes` value (`scripts/tailscale-configure.sh`) and the console
nameserver / AdGuard rewrite.

## Tailscale advertised routes

- `192.168.50.0/24` — the LAN subnet route (covers NAS, DSM, Traefik, clients).
- Exit node — encoded as `0.0.0.0/0` and `::/0` in prefs.

Both must be **approved in the admin console** to take effect.

## DNS

- **Tailnet:** admin console → DNS → global nameserver `192.168.50.254`
  (AdGuard). This applies AdGuard filtering to all tailnet DNS and resolves the
  service hostnames.
- **AdGuard rewrite** (in the `vesta` repo): `*.admin.lorenzopieri.dev →
  192.168.50.254`. One global rule, correct for **both** LAN clients (reach
  `.254` over the switch) and tailnet clients (reach `.254` via the subnet
  route) — they resolve to the same address, so there is no split-horizon
  problem.
- **Router:** `--accept-dns=false` keeps Tailscale from touching the router's
  own dnsmasq, which serves the LAN.

## Firewall

- Kernel-mode Tailscale inserts custom iptables chains (`ts-input`,
  `ts-forward`, NAT POSTROUTING marking) for subnet routing and the exit node.
- Merlin rebuilds iptables on every firewall restart, flushing those chains;
  `/jffs/scripts/firewall-start` reinstates them (see `tailscale-setup.md` §2.2).

## SNAT (`--snat-subnet-routes`, on by default)

When a tailnet client reaches a **physical LAN device** through the subnet
router, SNAT makes that device see the connection as coming from the router's
LAN IP, so it replies to the router (reachable) instead of to a `100.64.0.0/10`
address it has no route back to. Leave it on unless every LAN device has an
explicit route for the tailnet CIDR. (For `.254` specifically it is moot in some
paths, but it still matters for the rest of the /24.)

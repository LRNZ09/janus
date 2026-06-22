# Disaster recovery & rebuild

The point of this repo is that a wiped or replaced router becomes a copy-paste
restore. Three artifacts configure the router, and they live in **different
storage domains with different failure modes** — none of them holds secrets.

## The three artifacts and where they live

| Artifact | On-router path | Storage | Survives | Lost on |
| --- | --- | --- | --- | --- |
| `S06tailscaled` (kernel-mode edits) | `/opt/etc/init.d/S06tailscaled` | USB / Entware (`/opt`) | firmware reflash | `opkg upgrade tailscale`; USB drive failure |
| `firewall-start` | `/jffs/scripts/firewall-start` | internal flash (`/jffs`) | routine firmware upgrade | factory reset; "Format JFFS partition"; some major-version migrations |
| `tailscale up ...` (one-time config) | nowhere on the router | — | nothing | always, unless saved here |

Note: `/jffs` **does** survive a normal Merlin firmware upgrade (it is a
separate partition). It is lost only on a factory reset, a JFFS format, or a
migration that advises a clean reset. Merlin only auto-runs user scripts from
`/jffs/scripts`, so `firewall-start` cannot be relocated to the more durable
`/opt` and still fire — backing up its text (here) is the realistic answer.

## Recovering the effective config from a live node

Before resetting or reflashing, dump the running prefs so nothing is guessed:

```sh
tailscale debug prefs    # AdvertiseRoutes, exit node, CorpDNS, RunSSH, etc.
tailscale status         # runtime view
```

## Rebuild from zero

1. Flash **Asuswrt-Merlin**; attach the **USB drive**; install **Entware** (`amtm`).
2. Enable **JFFS custom scripts** (Administration → System).
3. `opkg update && opkg install tailscale`.
4. Apply `config/S06tailscaled` to `/opt/etc/init.d/S06tailscaled`.
5. Apply `scripts/firewall-start` to `/jffs/scripts/firewall-start`; `chmod +x` it.
6. `/opt/etc/init.d/S06tailscaled start`.
7. Run `scripts/tailscale-configure.sh` (the one-time `tailscale up`) and
   authenticate via the printed URL.
8. In the admin console: approve the subnet route + exit node, disable key
   expiry, set the global nameserver. (If reusing the same machine name,
   Tailscale will reuse the existing node.)
9. Reboot and verify (`docs/tailscale-setup.md` §8): the node should return on
   its own.

## State backup (optional)

`tailscaled.state` (`/opt/var/tailscaled.state`) holds the node key and prefs.
Backing it up lets a rebuild reconnect as the *same* node without re-auth, but
it is machine-secret material — keep it **out of git** (it is `.gitignore`d) and
store it somewhere encrypted if you back it up at all. Re-authenticating
interactively is the simpler, secret-free path.

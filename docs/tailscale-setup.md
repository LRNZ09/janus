# Tailscale on Asuswrt-Merlin — setup

Canonical reference: the Asuswrt-Merlin wiki, *Installing Tailscale through
Entware*. This document records the specific, working configuration for this
homelab and the rationale behind each choice.

## Prerequisites

- **Asuswrt-Merlin** flashed (stock ASUS firmware cannot run extra software).
- A **USB drive** for Entware + persistent state.
- **Entware** installed (via `amtm`). Its boot integration is what autostarts
  the Tailscale init script later.
- **JFFS custom scripts** enabled: Administration → System → *Enable JFFS custom
  scripts and configs* → Yes.
- **SSH** access to the router.
- The `tun` kernel module is available (the router supports OpenVPN, which uses
  it), so **kernel mode** works.

## 1. Install

```sh
opkg update
opkg install tailscale
```

`ca-bundle` is pulled in automatically as a dependency (needed for TLS to the
coordination server). There is **no separate `tailscaled` package** — the daemon
ships inside `tailscale`. (Routers on kernel 2.6 would use `tailscale_nohf`
instead; the GT-AX6000 does not.)

## 2. Kernel vs. userspace mode

Kernel mode is the **default** and is preferred here for subnet-router / exit-
node throughput. Userspace mode (`--tun=userspace-networking`) is the **fallback**
for stability on constrained routers — it touches no iptables at all, which also
sidesteps the kernel-mode crash documented in `troubleshooting.md`, at the cost
of performance.

This homelab runs **kernel mode** (`NetfilterMode: 2`).

### 2.1 Init script (`/opt/etc/init.d/S06tailscaled`)

For kernel mode, ensure these lines (full file in `config/S06tailscaled`):

```
ENABLED=yes
PRECMD="modprobe tun"
ARGS="--state=/opt/var/tailscaled.state --statedir=/opt/var/lib/tailscale"
PREARGS="nohup"
```

`ENABLED=yes` is what lets Entware's `rc.func` autostart the daemon on boot.
State lives on the USB/Entware mount (`/opt/...`) so it survives a firmware
reflash.

> **Maintenance gotcha:** `opkg upgrade tailscale` **overwrites** this file.
> Reapply these lines after any package upgrade, then
> `/opt/etc/init.d/S06tailscaled restart`.

### 2.2 `firewall-start` (`/jffs/scripts/firewall-start`)

Kernel-mode Tailscale inserts iptables chains. The router **flushes and rebuilds
iptables whenever its firewall service restarts** (on boot, WAN reconnects, and
some setting changes), which wipes Tailscale's chains. This script reinstates
them (full file in `scripts/firewall-start`):

```sh
#!/bin/sh
if [ -x /opt/bin/tailscale ]; then tailscale down; tailscale up; fi
```

A bare `tailscale up` re-applies whatever prefs are saved in state, so the flags
are not duplicated here. (A lighter alternative that avoids bouncing the tunnel
is in `troubleshooting.md`.)

## 3. Start the daemon

```sh
/opt/etc/init.d/S06tailscaled start
```

## 4. Configure + authenticate (one-time)

This is a **one-time** task; the flags persist in state and are re-applied on
every boot. See `scripts/tailscale-configure.sh`.

```sh
tailscale up \
  --advertise-routes=192.168.50.0/24 \
  --advertise-exit-node \
  --accept-dns=false \
  --ssh
```

| Flag | Why |
| --- | --- |
| `--advertise-routes=192.168.50.0/24` | Makes the router the subnet router for the whole LAN. This /24 already contains the NAS, DSM, and Traefik's `.254`, so all of them come along. |
| `--advertise-exit-node` | Offers the router as an internet exit node. In `tailscale debug prefs` this appears as the routes `0.0.0.0/0` and `::/0` — that is the encoding of an exit node, **not** a stray full-tunnel route. |
| `--accept-dns=false` | Keeps Tailscale from overriding the router's own dnsmasq resolver. Tailnet DNS is configured in the admin console instead (see below). |
| `--ssh` | Enables Tailscale SSH **to the router** (host mode → targets the router itself). |
| *(`--snat-subnet-routes`)* | **On by default** — left implicit. Makes other physical LAN devices see subnet-routed connections as coming from the router (reachable) rather than a `100.x` address they can't route back to. See `network.md`. |

Do **not** add `--accept-routes`: this node is a route *provider*, not a
consumer. The health line `Some peers are advertising routes but
--accept-routes is false` is **informational and expected** — it refers to
*other* nodes advertising routes, which this router correctly ignores.

Open the printed login URL and authenticate the node.

## 5. Admin console (manual; cannot be scripted from the router)

1. **Machines → `gt-ax6000` → Edit route settings:** approve the
   `192.168.50.0/24` subnet route **and** the exit node. Until approved, the
   route is advertised but inert, and `tailscale status` looks identical either
   way.
2. **Disable key expiry** on this node, so an always-on infrastructure router
   does not silently drop off the tailnet when its key ages out (~6 months).
3. **DNS → global nameserver `192.168.50.254`** (AdGuard Home on the NAS),
   giving the tailnet AdGuard-filtered DNS. The matching AdGuard rewrite
   (`*.admin.lorenzopieri.dev → 192.168.50.254`) lives in the `vesta` repo.

## 6. Boot persistence

No custom launcher and no `post-mount` hook are needed:

- Entware autostarts `/opt/etc/init.d/S06tailscaled` on boot (`ENABLED=yes`).
- The daemon reconnects from persisted state — **no `tailscale up` on boot**.
- `firewall-start` reinstates the iptables rules after the firewall rebuilds.

## 7. Updating Tailscale

- **Via Entware:** `opkg update && opkg upgrade tailscale`, then reapply the
  `S06tailscaled` edits (§2.1) and `S06tailscaled restart`.
- **Directly from Tailscale** (`tailscale update`): the Merlin wiki mildly
  discourages this on compatibility grounds, but it is the correct fix when the
  Entware package itself is broken (see `troubleshooting.md`). After a direct
  update, do **not** `opkg upgrade tailscale` until Entware ships a known-good
  version, or the bad package returns.

## 8. Verify

```sh
tailscale status            # node online, "offers exit node"
ps w | grep '[t]ailscaled'  # exactly one daemon, launched with the init args
tailscale debug prefs       # AdvertiseRoutes, exit node, CorpDNS:false, RunSSH:true
```

Then from a device **on the tailnet but off the LAN** (phone on cellular):
reach `192.168.50.254` (Traefik), reach DSM's real IP, and select the router as
exit node briefly to confirm egress.

# Architecture & rationale

## Goals

1. Reach the homelab's self-hosted services over Tailscale, by hostname, with
   real TLS (no port suffix in the URL).
2. Reach the **rest of the physical LAN** over Tailscale, including the NAS's
   own management UI (Synology DSM).
3. Use the homelab as a Tailscale **exit node** for internet egress.

## The constraint that shapes everything: macvlan isolation on the NAS

The NAS (Synology DSM) runs the services in Docker behind Traefik. Traefik needs
ports 80/443, but DSM already occupies them on the host, so Traefik is given its
own L2 identity on the LAN via a **macvlan** interface at `192.168.50.254`.
AdGuard Home shares that same network namespace / address so it can own `:53`.

macvlan has a deliberate kernel rule: **a macvlan child and its parent host
cannot talk to each other.** A container on `eth0`'s macvlan (Traefik at `.254`)
is unreachable *from the NAS host*, and the NAS host is unreachable *from the
container*. Other physical devices on the LAN are unaffected — this isolation is
strictly host ⟷ its-own-macvlan-children.

This is why Tailscale **cannot** simply run on the NAS:

- **Host-mode** Tailscale on the NAS shares the host's netns → it inherits the
  host's inability to reach `.254`. Services unreachable.
- **Co-located** Tailscale (sharing Traefik's netns to get `.254`) can reach the
  services, but then cannot reach the **host** → DSM unreachable.

With a **single NIC** on the NAS, the usual escapes don't apply:

- A second NIC would let the macvlan parent and the host's Tailscale sit on
  different interfaces (no isolation) — not available.
- A host-side macvlan **shim** interface bridges host ⟷ macvlan, but is an extra
  piece of host plumbing.
- **Freeing DSM's 80/443** so Traefik can use the host network directly requires
  editing Synology's nginx templates plus a boot script, and is overwritten by
  DSM updates — fragile.

## The resolution: run Tailscale on the router

The **router is the default gateway (`192.168.50.1`) and a separate L2 device**
on the switch. It is therefore *not* the macvlan parent host, so the isolation
rule does not apply to it. From the router, every destination is reachable
normally:

- Traefik's macvlan IP `192.168.50.254` (clean `:443`),
- the NAS's own LAN IP / DSM,
- every other physical device on the LAN.

So Tailscale runs **on `janus` (the router)** as the subnet router and exit
node. **The NAS needs no Tailscale container at all.** This dissolves the
isolation problem rather than working around it, and adds zero modification to
the NAS host.

## Topology

```
                              Internet
                                 │
                        ┌────────┴─────────┐
                        │   GT-AX6000      │  ← janus (this repo)
                        │   Asuswrt-Merlin │     Tailscale subnet router
                        │   Entware        │     + exit node
                        │   Tailscale      │     advertises 192.168.50.0/24
                        │   gateway .1     │     + exit node (0.0.0.0/0, ::/0)
                        └────────┬─────────┘
                                 │  LAN 192.168.50.0/24  (L2 switch)
              ┌──────────────────┼───────────────────────┐
              │                  │                        │
        ┌─────┴──────┐    ┌──────┴──────┐          other physical
        │ Synology   │    │  clients    │          LAN devices
        │ DSM (NAS)  │    └─────────────┘
        │  ← vesta   │
        │ Docker:    │
        │  Traefik   │  macvlan .254  ─── :443  services (Vaultwarden,
        │  AdGuard   │  (shared netns)   :53   DNS   Jellyfin, JDownloader2…)
        └────────────┘
```

The router, being a separate device at `.1` on the switch, reaches `.254` and
DSM without ever crossing the macvlan host-isolation boundary.

## Result

- Services on clean `:443` URLs (`*.admin.lorenzopieri.dev`).
- Full LAN reachable over the tailnet, DSM by its real IP.
- Exit node for internet egress.
- **Zero modification to the NAS host** — no shim, no port-freeing, no
  `ip_forward` sysctl, no Tailscale container on the NAS.

## Tradeoffs accepted

- Tailscale is installed via **Entware on Merlin**, whose package lags upstream
  and is occasionally a pre-release; updates are partly manual (see
  `docs/tailscale-setup.md` and `docs/troubleshooting.md`).
- Subnet-router and exit-node **throughput is bounded by the router CPU**. The
  GT-AX6000 (quad-core) handles this comfortably for normal use; very large
  exit-node transfers will feel the ceiling more than a NAS would.

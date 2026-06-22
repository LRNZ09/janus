# janus

Configuration, documentation, and automation for the **network perimeter** of
the homelab: an **ASUS GT-AX6000** running **Asuswrt-Merlin**, **Entware**, and
**Tailscale** as a **subnet router and exit node**.

> **janus** — the Roman god of doorways, gates, and transitions, depicted with
> two faces looking in opposite directions: an apt emblem for a router that
> watches both the WAN and the LAN. The NAS and the self-hosted services live in
> a separate repository, [`vesta`](https://github.com/LRNZ09/vesta) — Vesta being
> the goddess of the hearth and the protected centre of the home. Together they
> split the homelab into *threshold* and *interior*.

## What lives here

- The **rationale and topology** of the whole remote-access design
  (`docs/architecture.md`).
- The full **Tailscale-on-Merlin** install and configuration procedure
  (`docs/tailscale-setup.md`).
- **Network, firewall, and DNS** facts and assumptions (`docs/network.md`).
- **Troubleshooting** for the issues actually hit during setup, including the
  kernel-mode Entware crash (`docs/troubleshooting.md`).
- A **disaster-recovery / rebuild-from-zero** runbook and the storage-domain
  map that explains what survives which kind of wipe (`docs/disaster-recovery.md`).
- The **router-side files** themselves: the edited `S06tailscaled` init script
  (`config/`) and the `firewall-start` + one-time configure scripts (`scripts/`).

## Quick start

This repo is documentation + the small set of files that configure the router;
it is **not** a turnkey installer (flashing firmware and authenticating
Tailscale are interactive, one-time, manual steps). Read, in order:

1. `docs/architecture.md` — why Tailscale runs on the router at all.
2. `docs/tailscale-setup.md` — the actual procedure.
3. `docs/network.md` — addresses and assumptions to adjust for your environment.

## Repository layout

```
janus/
├── README.md
├── LICENSE
├── .gitignore
├── docs/
│   ├── architecture.md       # design story + topology
│   ├── tailscale-setup.md    # install → configure → verify
│   ├── network.md            # subnets, firewall, DNS, assumptions
│   ├── troubleshooting.md    # known failures + fixes
│   └── disaster-recovery.md  # rebuild runbook + storage domains
├── config/
│   └── S06tailscaled         # deploy to /opt/etc/init.d/S06tailscaled
└── scripts/
    ├── tailscale-configure.sh  # one-time `tailscale up` (NOT auto-run)
    └── firewall-start          # deploy to /jffs/scripts/firewall-start
```

## Before you publish this repo

This is intended to be public, so it deliberately contains **no secrets**:

- Tailscale is authenticated **interactively** (browser login URL), so there is
  **no auth key** in the repo. If you ever switch to `--authkey=tskey-...`, that
  value is a secret — never commit it; keep it in an ignored `.env`.
- No tailnet identifiers (node IDs, 100.64.0.0/10 addresses, login email) are
  stored here; they add nothing to the docs and are account-specific.
- The only environment specifics committed are an RFC 1918 LAN subnet and the
  public service domain (already discoverable via Certificate Transparency logs
  for the issued TLS certs). Review `docs/network.md` and redact if you'd rather
  not publish even those.

## License

[MIT](./LICENSE).

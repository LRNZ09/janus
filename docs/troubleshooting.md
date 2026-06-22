# Troubleshooting

## Daemon crashes on start in kernel mode — `AddConnmarkSaveRule` nil panic

**Symptom.** `tailscale up` prints the auth URL, then `tailscaled` dies; the
foreground daemon log shows, just before the crash:

```
router: enabling connmark-based rp_filter workaround
panic: runtime error: invalid memory address or nil pointer dereference
...
tailscale.com/util/linuxfw.(*iptablesRunner).AddConnmarkSaveRule(...)
```

Every iptables frame in the trace has a nil (`0x0`) receiver.

**Cause.** Not a config or a missing-iptables problem. Merlin's built-in
`iptables` (e.g. `v1.4.15`) is fine. This is a **bug in the Entware Tailscale
build** — a pre-release that mishandles the connmark / `rp_filter` workaround in
the iptables **mangle** table. It affects **kernel mode only**, not userspace
mode.

**Fix.** Update to a fixed upstream stable (the bug was resolved by ≈ `1.96.4`),
pulled directly from Tailscale's servers, over the broken Entware binary:

```sh
tailscale update                       # swaps the binary; daemon need not be running
/opt/etc/init.d/S06tailscaled restart
```

then re-run the one-time `tailscale up ...`.

**Caveats.** Do **not** `opkg upgrade tailscale` afterwards until Entware ships
a known-good package — it would reinstate the broken version. Re-run
`tailscale update` if it ever does.

**Or** sidestep entirely with **userspace mode**: set `--tun=userspace-networking`
in the `S06tailscaled` `ARGS` and drop `firewall-start` (userspace touches no
iptables). This trades subnet-router / exit-node throughput for immunity to the
bug.

## Diagnosing a daemon that won't start

Run it in the foreground to see the real error:

```sh
/opt/etc/init.d/S06tailscaled stop
killall tailscaled 2>/dev/null
rm -f /opt/var/run/tailscale/tailscaled.sock     # clear stale socket
tailscaled --state=/opt/var/tailscaled.state --statedir=/opt/var/lib/tailscale
```

Common culprits:

- **TUN missing** — `lsmod | grep -w tun` and `ls -l /dev/net/tun`. If absent,
  `modprobe tun` failed and the interface can't be created.
- **Out of memory** — `dmesg | tail -30` and `free -m`. Kernel-mode Tailscale is
  memory-hungry; constrained routers can OOM-kill it.
- **Earlier failure logged** — `grep -i tailscale /tmp/syslog.log`.

## "Some peers are advertising routes but --accept-routes is false"

**Benign.** It refers to *other* nodes advertising routes; this router is a
provider, not a consumer. Leave `--accept-routes` off.

## Route/exit node advertised but unusable

Approve them in the admin console (Machines → Edit route settings). `tailscale
status` looks the same approved or not, so this is the easy step to forget.

## Node drops off the tailnet after a few months

Key expiry. Disable key expiry on the router node in the admin console.

## Lighter `firewall-start` (avoid bouncing the tunnel)

`tailscale down; tailscale up` fully disconnects/reconnects the node every time
`firewall-start` fires (boot, WAN reconnects, some changes). To rebuild only the
netfilter rules without dropping the tunnel:

```sh
tailscale set --netfilter-mode=off
tailscale set --netfilter-mode=on
```

This leans on a documented side effect rather than a blessed "reinstate rules"
command (there is no such single command — the upstream feature request is
still open). Verify `tailscale set` exposes `--netfilter-mode` on your build.
The wiki's `down; up` remains the well-tested default; switch only if mid-
session `firewall-start` events cause noticeable drops.

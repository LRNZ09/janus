#!/bin/sh
#
# One-time Tailscale configuration for the GT-AX6000 subnet router + exit node.
#
# This is NOT auto-run. Run it by hand once after install, and again only after
# a `tailscale up --reset`, a lost/corrupted state file, or a router rebuild.
# The flags persist in /opt/var/tailscaled.state and are re-applied on every
# boot, so day-to-day operation needs nothing here.
#
# Authentication is interactive: this prints a login URL. Do NOT add an
# --authkey here in a public repo (it is a secret).
#
# After running, approve the subnet route + exit node in the Tailscale admin
# console and disable key expiry on this node. See docs/tailscale-setup.md.
#
# Adjust the subnet below if your LAN is not 192.168.50.0/24.

tailscale up \
  --advertise-routes=192.168.50.0/24 \
  --advertise-exit-node \
  --accept-dns=false \
  --ssh

# Notes:
#   --accept-dns=false  : do not let Tailscale override the router's dnsmasq.
#   (--snat-subnet-routes is ON by default and intentionally left implicit.)
#   Do NOT add --accept-routes: this node provides routes, it does not consume
#   them. The "peers are advertising routes" health message is expected.

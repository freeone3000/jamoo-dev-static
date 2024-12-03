---
share: true
date: 2024-12-03
---
# NixOS WTF

## Incomprehensible Problems

This is a simple collection of the incomprehensible problems I ran into trying to get NixOS booting on actual physical hardware.
I'm not sure what people are running it on to test, but it isn't physical hardware (due to the below difficulties) and it isn't
proxmox (due to *other* difficulties)... completely incomprehensible.

- `nixos-rebuild` errors are impenetrable
- `nixos-rebuild list-generations` shows a lot of internal info, including the hash, but doesn't allow for a tag or a date or any description of the change
- `nixos-rebuild switch --rollback` needs network if a package was since purged
- There's actually no way to rebuild the system without network if the network package was removed, even to a known-good configuration
- You *need* graphical output, even without x11! `nomodeset` doesn't prevent the framebuffer from trying to steal a graphics device!
- Documentation inconsistencies - `libvirt` documentation says to set up the bridge with an XML file, but bridges now exist in `networkd` and in domain scripts; the XML file isn't read
- `nixos-rebuild` has sanity checks that you might be fucking up your system... but then it continues anyway! there's not even a prompt, it just warns *and then does the thing it was warning you about*!
- "s" vs "z" (localization issue) - "authorizedKeys" but "virtualisation". If Nix is taking responsibility for all configs, it should have a consistent spelling. Choose a country.
- Cannot install programs per-user -- even simple programs require a complete rebuild?
  - does flakes fix this?
  - well, okay, but flakes are themselves marked experimental *despite* having widespread need for support
- no easy way to derive from github packages
- install `tmux` plugins? `git` plugins? `zsh` plugins?
  - how much of this is fixed by home-manager?
    - isn't that another flake-based solution?
- the graphical installer doesn't work under proxmox?
- the graphical installer has instructions instead of a script?
  - which **also** doesn't work under proxmox?!

## Possible Solutions

- Integrate git more closely with the OS - 1:1 mapping between git commit and configuration *enforced by the os* rather than by convention
- Figure out a solution to the problem that `flakes` solve and implement that upstream
- Figure out a solution to the problem that `home-manager` solves and implement that upstream
- Make `nixos-rebuild` actually stop if it's going to break the system
- sanity checks for the new OS config before it's actually switched to; swap back if it doesn't immediately work.
  - use a disk-level snapshot for this
- tighter integration with either btrfs or zfs snapshots for rollback
- actually have an actual computer, possibly two, running this IRL
- also test on hypervisors: proxmox, vmware, and (eurgh) hyper-v
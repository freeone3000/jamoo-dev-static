---
share: "true"
---
Noticed the NAS was running a rather high load. Rather than something destructive with my files or something persistent to steal data, they gave themselves away by... running a cryptominer? It was Ravenpool, by the way, absolute bastards.

I examined the rest of the network for activity using OPNSense traffic monitor, and detected no abnormal outgoing traffic. As Mumei was exposed to the internet, it did not have credentials to any other system, and was reverse-firewalled to only allow incoming connections to other machines on the network, no outgoing. Deny-by-default to local network is a rule I'm now recommending and using in the face of ongoing cyberattacks: the local network is saf*er*, but not *safe*.

Mumei got re-imaged. It was going to be with NixOS using fake IPMI (due to issues with vPro...), but that was scrapped due to the inability to have VMs as a persistent image, and the inability for NixOS to boot without a graphics card. (Why?) The entire [NixOS WTF](NixOS%20WTF.md) log is here.

Next was to try a level-1 hypervisor. Between ProxMox and Hyper-V, I wanted to try the "weird" one, and went with Hyper-V. Admin was a breeze, by following this [simple guide to setting up Hyper-V on a workgroup](https://www.tommycoolman.com/2022/01/22/managing-hyper-v-server-in-a-workgroup-environment/), I was able to admin the VMs using a native MMC right in Windows! Unfortunately, I was then managing a Hyper-V cluster with powershell. Still not the best use of time. I considered proxmox, but level-1 hypervisors seem overkill.

The solution I settled on was TrueNAS Scale. It allowed direct and secure access to the files, which is key because Mumei is still primarily a NAS, albeit an overprovisioned one. I set up the storage settings, imported the zpool, and everything was gucci! One caveat: TrueNAS **requires** all mutable user data to be on a separate drive from TrueNAS itself. This means /bulk is being used not only for media files, but also for applications, VMs, and anything else I'll want to run on there. At a future point, it might be worth adding in another SSD or two or three to the system. Regardless, my files were then exported, I now have better management and visibility, and a few `mv` commands later, I was even able to set up separate "Storage Spaces" in TrueNAS for various media data, allowing for the creation of a `tv` account for readonly access over SMB (for sharing with, ex, VLC on AppleTV).

VM setup was simple, and here's where we actually run NixOS as our kubernetes manager :) It's now set up as the k3s manager, with Lucy as a node. This should allow dynamic job provisioning for compute across the workloads in case I end up running jobs in the future! A WSL environment on Horo is currently set up as the kubectl manager, but clients are endlessly mutable; the Mac Mini is seeing more and more use these days as a development machine, so we'll see how that goes.



---
share: true
title: Setting up a bitcoin mining rig as an AI inference platform
date: 2024-07-30
categories:
  - Engineering Work
  - Personal Projects
---
# Setting Up a Home AI Server using a Bitcoin Mining Rig
***tl;dr**: just buy a mac mini, it'll do this better*

I'm interested in model experimentation, but paying overhead for remote servers and per-use calls seems silly to me. The breakeven point for this rig versus hosting on Colab is 300 hours counting only the VRAM capacity; if you need speed, there's no possible comparison.

## Goals:
- Total Budget $3000
- Can reasonably load models from huggingface
- Can inference at a reasonable rate

I ended up with a BTC-X79 motherboard off of AliExpress, which was *very cheap* due to sales. It comes with 256GB of SATA-keyed m2 storage, 4GB of system RAM, dual Xeon E5-2609s, and 8x PCI gen 3.0 slots of varying widths (from 4x to 16x). For now, five of these cards are populated with GeForce 3060s (due to power limitations in my walls for a single 15A circuit; more investment may happen if this turns out to be effective). The 3060 was chosen for a reasonable vRAM/$ -- fully loaded, this machine will have 96GB of VRAM for just under $2500 of cards. Titan XPs are cheaper, but don't offer significantly more capacity (48GB more VRAM) for significantly reduced performance (3x slower compute) and increased power consumption (325W instead of 215W). All things are trade-offs; this hit an ideal price point for now. In the future, offerings from AMD or Intel might be good drop-in replacements ^^.

(Kidding, obviously -- most of the expense in this thing was the cards and my time getting it up and running. If we have to reconfigure this thing ever, going cloud-based should have dropped in price enough that the break-even is further out.)

For inference, we don't actually need to transfer the model to the GPUs that often -- we're transferring (relatively) small quantities of data between GPUs infrequently, and keeping the models resident. So the low transfer speeds won't affect us that much.

## Getting it Powered and Networked
Power is going to be a single Corsair 1600W 80+ Gold PSU. We're going to use every watt, so 1600W isn't overkill in this case. 

Networking was more complicated. The initial idea of using a wireless dongle was stymied by Ubuntu hanging on boot if it doesn't have network. This was not solved by installing the firmware or configuring network manager. I tried for a day or two to fix it, with a spare laptop wired up as an ersatz wifi-to-ethernet adapter, but unfortunately fighting with Ubuntu yields no good results[^1]. I've settled on a 1GBe powerline adapter from TP-Link wired into my [home network](%{link Home Networking Setup.md %}), connected to the ethernet port.

[^1] At this point, why am I using Ubuntu at all? Because all of the ML hacker stuff is designed for Ubuntu. Not debian, not RHEL, and decidedly not arch. Dockerized? Surely not. Running nix native? Good luck passing *all* of your GPUs through nix stably! Last time I tried, I couldn't stabilize that either. So save running OpenStack or vSphere as baseline, this is the best we can do. My time for personal projects is no longer infinite.

## Software and Hardware
Step one, as per usual, is getting `nvidia-smi` to play nice. `nvidia-drivers-570-server` was the newest, and Ubuntu keeps bugging me to update, but `nvidia-drivers-540-server` was the most recent that worked with DKMS, my current kernel, the CUDA version I need, and had a stable `nvidia-smi` across boots, so that's the version I'm using.

As for the cards, here's an output of `dmidecode`:
```bash
jasmine@lucy:~$ sudo dmidecode | grep 'PCI'
                PCI is supported
        Internal Reference Designator: J9C1 - PCIE DOCKING CONN
        Type: x4 PCI Express
        Type: x8 PCI Express
        Type: x8 PCI Express
        Type: x8 PCI Express
        Type: x16 PCI Express
Invalid entry length (0). DMI table is broken! Stop.
```

Oh. <span style="color: orange;">China</span>.

But nvida-smi works!
```shell
jasmine@lucy:~$ nvidia-smi
Fri Apr 26 19:26:17 2024
+---------------------------------------------------------------------------------------+
| NVIDIA-SMI 535.161.08             Driver Version: 535.161.08   CUDA Version: 12.2     |
|-----------------------------------------+----------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |         Memory-Usage | GPU-Util  Compute M. |
|                                         |                      |               MIG M. |
|=========================================+======================+======================|
|   0  NVIDIA GeForce RTX 3060        Off | 00000000:01:00.0 Off |                  N/A |
|  0%   37C    P0              32W / 170W |      0MiB / 12288MiB |      0%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   1  NVIDIA GeForce RTX 3060        Off | 00000000:03:00.0 Off |                  N/A |
|  0%   34C    P0              29W / 170W |      0MiB / 12288MiB |      0%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   2  NVIDIA GeForce RTX 3060        Off | 00000000:81:00.0 Off |                  N/A |
|  0%   30C    P0              35W / 170W |      0MiB / 12288MiB |      0%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   3  NVIDIA GeForce RTX 3060        Off | 00000000:82:00.0 Off |                  N/A |
| 30%   30C    P0              30W / 170W |      0MiB / 12288MiB |      0%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   4  NVIDIA GeForce RTX 3060        Off | 00000000:83:00.0 Off |                  N/A |
|  0%   41C    P0              37W / 170W |      0MiB / 12288MiB |      0%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
|   5  NVIDIA GeForce RTX 3060        Off | 00000000:85:00.0 Off |                  N/A |
| 53%   33C    P0              32W / 170W |      0MiB / 12288MiB |      0%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+

+---------------------------------------------------------------------------------------+
| Processes:                                                                            |
|  GPU   GI   CI        PID   Type   Process name                            GPU Memory |
|        ID   ID                                                             Usage      |
|=======================================================================================|
|  No running processes found                                                           |

```

This is a completely reasonable output. Nothing abnormal here. The PCI addresses are completely reasonable and in a reasonable range (they are not, but I don't really know what it means that they're not, so I'm continuing regardless).

Next up is loading on an actual model!

## Loading a Model
For our purposes, we'll be using llama.cpp, because it does our GPU allocation for us.

The primary issue with loading a model is that models are big, and this has...
```shell
jasmine@lucy:~$ df -h /
Filesystem                         Size  Used Avail Use% Mounted on
/dev/mapper/ubuntu--vg-ubuntu--lv   57G   13G   42G  23% /
```
Ah. So the seller on aliexpress lied about the quality of his goods. Looks like we're going to leverage the NAS in order to get some decent amounts of storage on here.

### NFS
For disk, I'm following following [the first guide I found on google](https://linuxconfig.org/how-to-configure-nfs-on-linux) to configure NFS on Mumei. I've done so, exporting `/bulk/exports/llm` to Lucy's static IP.

It can then mount the storage, and access it at the speed of the network.

### RAM
Ah, the sticky wicket. It has a 4GB SODIMM welded(!) to the motherboard. Since `llama.cpp` dislikes loading models streaming from disk, obviously we need to change ollama... 

Or, as a "temporary" measure, we can do hacks. We have the data on NFS on disk, so, what if we just load the model over the network? There's a trick for Mellanox cards (and *only* Mellanox cards) to use RDMA, but instead we fake it the other way and use swap-on-NFS to allow the model to be loaded into "RAM", and from there into VRAM. It is incredibly slow (five minutes to load a model!), but there's enough VRAM in this system for it to stay resident.

### Actually Running A Model
Inference results on ollama show results comparable to an M1 mac, but with much lower quantization, equivalent to having an M1 mac with ... 96GB of RAM. You can just buy that now, and it's much cheaper. I'd advise against trying this setup for *many many* reasons, the increasing power of quantized models and availability of NPUs on ARM chips included. There's no need for something like this anymore.





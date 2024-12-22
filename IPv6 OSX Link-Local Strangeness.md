---
date: 2024-12-22
title: IPv6 OSX Link-Local Strangeness
---
# IPv6 OSX Link-Local Strangeness

While working on a ~\*secret project\*~, I was in the situation where I wanted to send packets to my computer from a
bunch of different IPs. This ran me down a rabbit hole of OSX networking culminating in a bug report.

First attempt was to try IPv4, because we still reach for the outdated tools more often than we should. `lo` on linux
responds to the entire `127.0.0.1/8` subnet, as it should! OSX, however, only responds to the 127.0.0.1/32 *address*.
Trying to bind to any valid address in that subnet will respond with `LError 39`, address not available. 

We can add aliases using `ifconfig`, but this takes individual addresses instead of a subnet. After the third /16 was added
(programmatically, I'm not insane), I started experiencing system instability with regard to network access. Random programs
just sometimes simply could not access the internet! Removing the aliases and rebooting caused the problems to go away,
but it became clear that this is tenable only for a small number of addresses - likely a /24, maybe a /16, definitely
not the full /8.

So, I turned to IPv6. You would think that since `ifconfig` reports that it responds to `fe80::1/64`, that it would respond
to any address in that range. You would be wrong. The actual networking SDK gives back the proper response, that it
responds to `::1/128` and `fe80::1/128`. Oh no, oh dear, we're back to the IPv4 situation. I tried binding to other addresses
in `fe80::1/64` that `ifconfig` reported, but we get back an invalid bind again.

But wait! We can just use our *actual* IP, and route it to ourselves. `eno0` is my wifi card, with scope_id of `0xe`.
Remember that. I'm on a network that routes IPv6 packets but isn't set up for DHCP6 or SLAAC, so the interface actually
self-assigns an address of `inet6 fe80::8f1:f892:9152:9105%en0 prefixlen 64 secured scopeid 0xe`. Binding to other IPs
in `fe80::8f1:f892:9152:9105/64` works! So I go ahead with that bind, scope_id of 0xe, flow of 0, port of 12981 (chosen
by fair die roll). So, now we try to send a packet to this from the same machine, with the other end bound to `[::]:0%eno0`.
Failure.

So what gives? Maybe the bind is set up incorrectly. I try pinging it from my phone on the same network, and we get
success! It's *routable* as a link-local address, even in the absence of supporting infrastructure. Next step, checking
Wireshark to see what the issue is. We see that we're getting back ICMP results... on `lo0`. Because it's trying to route
"fe80::8f1:f892:9152:9106" to `lo0`! Even though I specified scope_id of `0xe`, it's still trying to route it to `lo0`!

This is actually similar behavior to the ipv6 stack in linux -- it *also* will switch interfaces of
link-local packets destined for the current machine via loopback. However, linux machines *accept packets routed this way*. 
FreeBSD shares the filtering behavior, so if you don't specify scope_id it will make the packet undeliverable, but it also
accepts scope_id when supplied. FreeBSD will also choose a physical interface over a loopback interface if the packet is in
the physical interface's ipv6 range, even when the physical interface's address is link-local (this may be by chance, 
but it 100% uses scope_id when supplied). This appears to be an OSX-only kernel netstack-specific interaction; Apple 
chose the driver behaviour of linux and paired it with the bsd netstack, which causes this issue.

This is a bug, and after talking with a friend who happens to work there, I've
[filed a Feedback Assistant report](https://feedbackassistant.apple.com/feedback/16143533). I'll update when I get any sort of response.
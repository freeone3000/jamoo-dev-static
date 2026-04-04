---
share: true
title: Caddy ACME Wildcard Challenges
date: 2025-01-25
categories: ["Engineering Work", "Self-Hosting Forays"]
---
# Caddy Acme Wildcard Challenges
I'm using Caddy as a reverse proxy, I wanted real certificates
on my homelab that validate in Safari, and I did not want to expose these actual servers to the internet.

An alternative would be using a local CA, and then getting all relevant computers to trust the services. This is not
*impossible*, but one of the devices I want to trust the services is an iPhone, and I haven't gone down the Apple Configuration
route yet. DNS-01 is more familiar to me, and also seemed a suitable solution as I do own the domain.

This was a fact-finding mission with several pitfalls, some of which may be bypassed if you're slightly more familiar
with the backing technologies. I likely have bypassed some of my own; here's the documented path that I took.

## Installing ACME-DNS
ACME-DNS requires recompiling caddy. The invocation for this looks like `xcaddy v2.9.1 --with github.com/caddy-dns/acmedns`. This will create a caddy binary with the acmedns plugin.
I then put it in /usr/local/bin/caddy; it works fine standalone.

If you're on Debian and using bash, you might have to run `hash -r` to remove the cached binary from bash (why is this a thing?).

You'll have to modify the caddy start script. Find its location with `systemctl status caddy.service`, and then execute
`sed -i s@/usr/bin/caddy@/usr/local/bin/caddy@g $(THAT_FILE)` to perform the change.

## Authenticating with ACME-DNS
Primarily, you should be [following their quite nice instructions](https://github.com/caddy-dns/acmedns).

ACME-DNS requires a JSON file to authenticate. Issue `curl -X POST https://auth.acme-dns.io/register > acme-dns.json` to
get the JSON file, which can then be linked to the Caddyfile.

## Writing the Caddyfile
My example below uses 'jamoo.dev' for the domain. As you do not own this domain, you should use a domain you do own.

The below matcher and handler syntax is used to have fewer domain validation requests. This issues two: one for
"melfina.jamoo.dev" and one for "*.melfina.jamoo.dev", instead of one per host.

As I'm running a fairly large number of hosts, it's better from a rate-limiting perspective (and a service liveness perspective,
as DNS challenges can take up to 5 minutes!) to request one cert for all subdomains. We also need one for the "root" subdomain,
which is unavoidable.

Your Caddyfile should look like:

```caddyfile
# acme-dns, see https://caddy.community/t/namecheap-with-acme-dns-provider/18944
# named matchers are used here to have one DNS challenge for the entire domain, and then use it for all subdomains.
melfina.jamoo.dev, *.melfina.jamoo.dev {
    tls {
        dns acmedns /etc/caddy/acme-dns.json    
    }
    
    @matcher1 {
        host host.melfina.jamoo.dev
    }
    handler @matcher1 {
        reverse_proxy service1:1234
    }
    
    @matcher2 {
        host thing2.melfina.jamoo.dev
    }
    handler @matcher2 {
        reverse_proxy service2:12555
    }
}
```
Run `caddy validate` *in /etc/caddy* to verify. If you get an error about JSON terminating too soon, it didn't find the
Caddyfile. There might also be a param to determine file location, but you can also `cd` into the target directory.

Then use `systemctl reload caddy` to reboot. 

## Validation
`curl -v host.melfina.jamoo.dev` to verify TLS certificate validity.

## I'm getting a TLS error and my cert is invalid
First, check `dig _acme-challenge.melfina.jamoo.dev TXT @8.8.8.8` to see if the challenge is being served. If it is, check
`dig melfina.jamoo.dev SOA` to determine the actual authoritative server. Mine was 100.100.100.100, from namecheap.
Namecheap *did* publish to 8.8.8.8, but *did not* resolve CNAMEs for TXTs on their own nameserver. For shame.

I switched to Cloudflare, and this problem went away. Don't use namecheap dns, I guess?


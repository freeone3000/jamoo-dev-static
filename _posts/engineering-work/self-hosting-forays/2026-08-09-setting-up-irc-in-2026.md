---
share: false
title: Setting up IRC in 2026
date: 2026-08-09
categories:
  - Engineering Work
  - Self-Hosting Forays
---
# Setting up IRC in the Year of Our Lord 2026

## Motivation
As Discord becomes increasingly gamified and data-harvesting, one of my friend groups started looking to alternatives - ones that are not explicitly social media, ones that did not require a centralized server harvesting and collecting information. Ones that weren't work-flavoured like Slack. Some efforts with XMPP or ATProto were discussed, but it seems like the best for real-time communication seems to be the venerable IRCv3.
## Desiderata
I strongly desire social connection and reachability to be available on my phone. Which means IRCv3 with replay is _close_ but not there. I’d ideally want a discord<->app bridge for classic connectivity. I’d want the chat history and read status to be shared across my devices. I’d really like asynchronous delivery. I’d really like file transfer. Voice and screenshare are also not optional. And I don’t want separate apps to deal with all of this. And it has to work on iPhone.
## So why IRC?
IRCv3 comes the closest and is the only thing with a working client that ships now. User experience matters, and matters greatly, especially for something that should be fun and friendly (chat with friends!) and used daily, or near-daily. It cannot be a half-baked laggy battery-draining mess (looking at you Element).
## Software
### Current SoTA for Clients
I used to have a great IRC client. Connected well, had full IRCv3 support, did network negotiation well. It was pulled from the app store for lack of updates, potentially because it was a 5-year-old client for a 30-year-old protocol and nothing needed to change. Nevertheless, our current app overlords push us onward to further and greater heights, so we must recommend a client that's actually available on the App Store. On iOS, that's goguma. It works well. It connects to a single server, acting as your bouncer. This removes part/join spam and also, when paired with tailscale, can act as an overlay proxy to ensure connectivity over hostile networks. This means we're setting up a bouncer.
### Current SoTA for Servers
After comparing various irc servers, we're going with [InspIRCd](https://www.inspircd.org/), due to it having significant capabilities but also real-world performance and good documentation.

My personal bouncer is soju, set up in a Dockerfile with in-built tailscale. We're using docker compose volumes for persistence, which is good enough for this use-case. These can be persisted externally via any file backup mechanism if additional durability is required. I run this through my local [Portainer](https://www.portainer.io) setup with a bog-standard [local docker repository](https://www.docker.com/blog/how-to-use-your-own-registry-2/). The docker repository is treated as ephemeral, and may be later upgraded if such a thing is desired - I'm keeping all of the source 😁 Note that you'll need to connect via `docker exec -it soju /bin/sh` and then run `sojudb create-user <username> -admin` to create a user on whichever server you're deploying to. (It should be possible to run sojudb under `docker exec -it`, but something gets confused in the pipes.)
## Use
I've been using it for a couple of days and it works well for IRCv3 servers like our private one, and even IRCv2 servers like liberachat. It's nice reconnecting with my old friends, and it's a lot less corporate than discord! However, it's not a perfect replacement: see the Future Work section.
# Future Work
## But IRCv3 doesn't do voice calls, which you said you wanted
I know 😭 It *should* be matrix. It really should be Matrix. But Element is bad. There are no alternative clients worth taking a look at. XMPP with Jingle? Maybe??
## Next Up
Next up I'll probably be working on some sort of useful client for XMPP with Jingle on iOS and desktop OSX. That's where I spend most of my time nowadays, and I think a natively integrated client is a good option. IRC was my first real program, after all, so why not revive that effort, and show what 25 years of experience can do when applied to a problem?
# Code Listings
Code, *but not post*, has been Co-Authored by Claude Opus 5. I do mean that literally - it tried three times to get something working before I stepped in and corrected its knowledge of networks and bashed the scripts into the right shape.
## `Dockerfile`
```dockerfile
####  
# soju IRC bouncer + tailscaled in a single container.  
#  
# Build and push to the local Artifactory registry, e.g.:  
#   docker build -t "$REGISTRY/soju-tailscale:latest" melfina/soju  
#   docker push "$REGISTRY/soju-tailscale:latest"  
####  
FROM alpine:latest  
  
# soju and tailscale both live in the community repo.  
RUN apk add --no-cache \  
        soju \  
        tailscale \  
        ca-certificates \  
        jq \  
        tini  
  
# /data holds the sqlite db and the message log; /var/lib/tailscale holds the  
# node key. Both are bind/volume mounted by the compose file — created here so  
# the container still starts if someone runs it without mounts.  
RUN mkdir -p /data/logs /var/lib/tailscale /var/run/tailscale /etc/soju  
  
COPY entrypoint.sh /usr/local/bin/entrypoint.sh  
RUN chmod +x /usr/local/bin/entrypoint.sh  
  
ENV TS_HOSTNAME=soju \  
    TS_STATE_DIR=/var/lib/tailscale \  
    SOJU_IRC_PORT=6697 \  
    SOJU_HTTP_PORT=8080  
  
# tini reaps the tailscaled child and forwards signals; without it soju runs as  
# PID 1 and `docker stop` degenerates into a 10s SIGKILL wait.  
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
```

## `entrypoint.sh`
```bash
#!/bin/sh  
#  
# Bring up tailscaled, learn our own MagicDNS name, generate soju's config from  
# it, publish soju through Tailscale Serve, then run soju.  
#  
set -eu  
  
: "${TS_AUTHKEY:?TS_AUTHKEY must be set (tskey-auth-...)}"  
TS_HOSTNAME="${TS_HOSTNAME:-soju}"  
TS_STATE_DIR="${TS_STATE_DIR:-/var/lib/tailscale}"  
SOJU_IRC_PORT="${SOJU_IRC_PORT:-6697}"  
SOJU_HTTP_PORT="${SOJU_HTTP_PORT:-8080}"  
TS_SOCKET=/var/run/tailscale/tailscaled.sock  
  
mkdir -p "$TS_STATE_DIR" /var/run/tailscale /data/logs /etc/soju  
  
# --tun=userspace-networking is important.  
# In userspace mode tailscaled owns nothing but its own socket,  
# so soju keeps Docker's DNS and the bridge default route for outbound, while  
# inbound tailnet traffic still arrives via Serve.  
tailscaled \  
    --state="${TS_STATE_DIR}/tailscaled.state" \  
    --statedir="${TS_STATE_DIR}" \  
    --socket="${TS_SOCKET}" \  
    --tun=userspace-networking &  
TAILSCALED_PID=$!  
  
SOJU_PID=""  
shutdown() {  
    [ -n "$SOJU_PID" ] && kill -TERM "$SOJU_PID" 2>/dev/null || true  
    kill -TERM "$TAILSCALED_PID" 2>/dev/null || true  
}  
trap shutdown TERM INT  
  
# Blocks until the node is authenticated. --accept-dns=false keeps tailscaled  
# away from /etc/resolv.conf even though we are in userspace mode; --accept-routes  
# is off so tailnet subnet routes can never shadow the IRC networks we dial out to.  
tailscale --socket="${TS_SOCKET}" up \  
    --authkey="${TS_AUTHKEY}" \  
    --hostname="${TS_HOSTNAME}" \  
    --accept-dns=false \  
    --accept-routes=false  
  
# Ask tailscaled what we ended up being called instead of hardcoding a  
# placeholder tailnet name that has to be filled in and redeployed.  
DNS_NAME="$(tailscale --socket="${TS_SOCKET}" status --json | jq -r '.Self.DNSName')"  
DNS_NAME="${DNS_NAME%.}"  
if [ -z "$DNS_NAME" ] || [ "$DNS_NAME" = "null" ]; then  
    echo "entrypoint: could not determine MagicDNS name from tailscaled" >&2  
    exit 1  
fi  
echo "entrypoint: tailnet name is ${DNS_NAME}"  
  
# Both listeners are plaintext on loopback; TLS is terminated by Tailscale Serve  
# below, and nothing is published to the Docker host.  
cat > /etc/soju/config <<EOF  
# Generated by entrypoint.sh on container start -- edits here do not persist.  
# https://soju.im/doc/soju.1.html  
listen irc+insecure://127.0.0.1:${SOJU_IRC_PORT}  
listen http+insecure://127.0.0.1:${SOJU_HTTP_PORT}  
hostname ${DNS_NAME}  
db sqlite3 /data/soju.db  
message-store fs /data/logs  
EOF  
  
# Optional escape hatch: bind-mount extra directives without rebuilding.  
if [ -f /etc/soju/config.extra ]; then  
    echo "entrypoint: appending /etc/soju/config.extra"  
    cat /etc/soju/config.extra >> /etc/soju/config  
fi  
  
# Reset first so repeated restarts do not accumulate stale mappings.  
tailscale --socket="${TS_SOCKET}" serve reset  
tailscale --socket="${TS_SOCKET}" serve --bg \  
    --https=443 "http://127.0.0.1:${SOJU_HTTP_PORT}"  
tailscale --socket="${TS_SOCKET}" serve --bg \  
    --tls-terminated-tcp="${SOJU_IRC_PORT}" "tcp://127.0.0.1:${SOJU_IRC_PORT}"  
  
echo "entrypoint: soju reachable at ircs://${DNS_NAME}:${SOJU_IRC_PORT} and https://${DNS_NAME}/"  
  
soju -config /etc/soju/config &  
SOJU_PID=$!  
  
# Exit as soon as *either* process dies so Docker's restart policy can act on it;  
# a live soju behind a dead tailscaled is unreachable but looks healthy.  
wait -n "$TAILSCALED_PID" "$SOJU_PID"  
STATUS=$?  
shutdown  
wait || true  
exit "$STATUS"
```
## `soju.yml`
```yaml
## soju IRC bouncer, published to the tailnet via Tailscale Serve.  
##  
## Required env vars (Portainer > Stack > Environment variables, or a .env  
## alongside this file):  
##   TS_AUTHKEY=tskey-auth-XXXXXX   reusable, pre-approved, non-ephemeral  
##   REGISTRY=melfina.jamoo.dev:5000       registry from registry.yml  
##   SOJU_TAG=latest                       optional, defaults to latest  
##  
##  
## Requires HTTPS certificates to be enabled for the tailnet  
## (https://login.tailscale.com/admin/dns) -- Serve cannot terminate TLS without it.  
name: soju  
  
services:  
  soju:  
    image: ${REGISTRY:-localhost}/soju-tailscale:${SOJU_TAG:-latest}  
    pull_policy: always  
    container_name: soju  
    restart: unless-stopped  
    environment:  
      - TS_AUTHKEY=${TS_AUTHKEY}  
      - TS_HOSTNAME=${TS_HOSTNAME:-soju}  
    volumes:  
      # sqlite db + message logs  
      - soju-data:/data  
      # tailscale node key; losing this re-registers the node under a new name  
      - tailscale-state:/var/lib/tailscale  
  
volumes:  
  soju-data:  
  tailscale-state:
```
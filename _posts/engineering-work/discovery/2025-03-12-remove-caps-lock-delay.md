---
title: Remove caps lock delay on OSX
categories:
  - Engineering Work
  - Discovery
share: true
---
# Remove caps lock delay on OSX

Run this command in any terminal:

`hidutil property --set '{"CapsLockDelayOverride":0}'`

You can put it in a script and have it run on login. You don't need a third-party tool or anything else, this is just a setting.
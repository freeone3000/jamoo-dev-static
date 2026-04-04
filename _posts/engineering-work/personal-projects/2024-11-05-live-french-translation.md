---
share: true
title: Live French Translation Project
categories:
  - Engineering Work
  - Personal Projects
---
# Live French Translation Project

The problem: I live in Quebec and I don't speak French

The solution: ~~Learn French~~ Overcome human limitations by exploiting boundless compute

## (EDIT: 2024-01-18) Didn't the Samsung Galaxy S24+ Ultra announce specifically this feature?
Yes, and I am mildly annoyed at a billion-dollar company implementing an idea that I, a hobbyist, am trying to solve for myself. I'm still going to *do* it, unless the phone launches first and I just buy it instead.

## Goals
- This must run in real-time
- Connect to a phone and translate fr-CA for Jasmine; then, relay Jasmine's responses back in French. (fr-CA preferred, but fr-FR acceptable)

## Tasks
1. Get audio working, *both channels*
	- We need a source channel and a destination channel -- iphone as *input*, then a headset as *output*, with this piece of code in the middle. Both bidirectional!
2. Test out various translation models. Get one that produces workable Quebecoi French! (And can *handle* quebecoi french)
	- This may require a cascade
3. Move the translation unit to a dedicated device, such as an rpi
	- If needed, move the models to a networked service
4. Test it out, tweaks and improvements
5. See if this can work outside the house??

Headers below organize the work -- struck out items are ones that didn't work!

## ~~Getting Bluetooth Working~~
First step, getting my linux desktop (which has a USB bluetooth device recognized by BlueZ) connected to the headphones. [This AskUbuntu Link](https://askubuntu.com/questions/2573/can-i-use-my-computer-as-an-a2dp-receiver-bluetooth-speaker#109533) looked promising, so I'm working off of that.
Debian doesn't seem to have `pulseaudio-bluetooth-discover`. Getting this working in an existing network stack seems to be **very hard**. I've placed an order for two ESP32 dev boards.

## ~~ESP32 Dev Boards (ESP32-S3-DevKitC-1-N32R8V)~~
~~Two were purchased, since each esp32 can act as a source or a sink but not both.~~

## ESP32 Dev Boards (ESP32-DevKitC-32E)
Two were purchased, since each esp32 can act as a source or a sink but not both. BT-LE is not the same as, and does not imply, BT4.2 support. iPhones do not yet support BT-LE Audio, so we need an actual BT4.2 chip for HSP support. The ESP32-WROOM-32E is the cheapest, and according to [the expressif systems product finder](https://products.espressif.com/#/product-selector?names=&filter=%7B%22Bluetooth%22:%5B%22BR/EDR%20+%20Bluetooth%20LE%20v4.2%22%5D%7D) it actually supports Bluetooth. Is this fast enough for HSP? [This github repo](https://github.com/atomic14/esp32-hsp-hf) says so! I'll be using it as a starting point (thank you GitHub License). I've gotten this working.
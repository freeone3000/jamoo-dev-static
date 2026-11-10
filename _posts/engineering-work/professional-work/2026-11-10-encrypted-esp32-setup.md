---
title: Encrypted ESP32 Setup
date: 2026-11-10
categories:
  - Engineering Work
  - Professional Work
share: true
---
# Encrypted ESP32 Setup
I love ESP32s. They're *so cheap* for what you get. They're excellent for prototyping - with BLE, WiFi, an ADC, and various digital signals ($I^2C$, SPI, etc) built in, they've probably already got what you need. It's thirty dollars for a devkit. And it's the basis for many other mid-power modules for embedded compute, with the underlying exposed. 

However, this does come with a downside - they're field-programmable via usb with two wires. This is bad. Luckily, most variants come with a method of encrypting flash and ensuring secure boot. Let's get into that.
#### Optional background
"efuses" are one-time burned-in data storage on an esp32. they can be set *once* during the lifetime of the device.
"popcnt", or population count, is the number of bits set.

All examples in this, and most of my other blogs, are in zsh. bash may be compatible, but not a guarantee. 

Every time I mention a security note, called out with ⚠️, this is a mistake that's common, logical, and will prevent the entire security chain from functioning. There will be a lot of these. Try it out on some of your own devices!
## Setup
### Our Hardware
We're using an ESP32-S3 as our base, chosen for unrelated reasons. This will also work on the ESP32-S2 and -C3, and likely on the -C6 and newer (I haven't tested). It will *not* work on the S2, the -WROOM, or older chips. A rule of thumb is if it has 4.2 instead of BLE, it will not have secureflash and relies on secureboot v1 without flash encryption. I don't recommend those for any application that trusts flash data as trusted (ie, anything executing code from it) since that opens you up to side attacks.

Since doing this out of order or making certain mistakes can **irrevocably brick your device**, I recommend (as with many hardware projects) having spares.
### Our software
As our flasher, we're using our standard ExpressIf idf.py flasher. We've also got a unixy system with access to openssl. As per usual, *losing encryption keys bricks the device*. So don't do that.
### Our Program
This was tested using a micropython program, but anything that generates an esp image will work here.
## Tasks
The below will set up an ESP32 for wired updates, which the documentation claims is for a development environment. Securing an OTA update is an entirely separate kettle of fish, since it essentially allows the esp32 to update *itself* via a mechanism primarily derived in your own code. We won't be setting that up here (a later article, perhaps).
### Encrypted Flash
Step one is to generate our keys. We need two keys: an AES-256 key for flash encryption, and an ECDSA key for secure boot. We need to flash our encryption efuses *first*, before we enable secure boot, because secure boot (sensibly!) prevents us from flashing additional fuses. **Do it in this order**.

This uses an XTS-AES key, which needs to be *double* the underlying. Thus, AES-256 requires a 512-bit key. 512-bit is 64 bytes. We generate with:
```bash
openssl rand 64 > flash_key.bin
```

A sensible thing to think would be that we burn an efuse with this value, encrypt the firmware, and push it over. This completely reasonable workflow is what we'll be using, but ⚠️ only after also setting the `SPI_BOOT_CRYPT_CNT` efuse to `3 (0b111)`, its max value, to ensure that the esp32 will only attempt to decrypt firmware signed with the efuse key.

> The "intended" use of `SPI_BOOT_CRYPT_CNT` is to track whether it's encrypting or decrypting on boot. For even popcnt, the content is unencrypted (0, 2, 4), and on odd popcnt the content is encrypted. When `flash_encryption` is first set, this triggers the esp32 to internally encrypt the flash contents, and then increment `FLASH_CRYPT_CNT` from `b000` (0) to `b001` (1). The next, unencrypted, flash will toggle to `b011` (2), telling it to again encrypt and move to `b111` (3). Evens, it will encrypt and reboot, odds, it will load encrypted. This is weird, slow (encryption takes like 2 minutes somehow despite decryption being milliseconds), causes odd reboots during a dev cycle. A careful reader may notice that an attacker can also *flash unencrypted firmware* and it will "helpfully" encrypt it for them! *Huge* security footgun.
> 
> (This is an improvement over the original ESP32, where unencrypted firmware can be flashed four times using `FLASH_CRYPT_CNT`. Here it can only be flashed once 🤦‍♀️)

```bash
espefuse.py burn_efuse SPI_BOOT_CRYPT_CNT 3
```

efuse burn is set by our tooling. `espefuse.py`, the esp-idf supplied tool for burning efuses on an esp32, takes three arguments: the key block, the encryption key, and the "key purpose", by which they mean the key size. Key blocks are in 256-bit segments, and since we want AES-256 via XTS-AES, we're using a 512-bit key which uses 2 blocks. There are five blocks, so we get two of our keys per esp32... theoretically.

```zsh
KEY_BLOCK="BLOCK_KEY0" # our second key would use 2. there's no space for a third.
FLASH_ENCRYPTION_KEY=$(cat flash_key.bin)
KEY_PURPOSE="XTS_AES_256_KEY"
espefuse.py --chip esp32s3 --port "$PORT" burn_key "$KEY_BLOCK" "$FLASH_ENCRYPTION_KEY" "$KEY_PURPOSE"
```
Leaving this unflashed allows someone to simply flash another key that they control, and encrypt there: ⚠️ We must burn *all* efuses, to prevent another write. (We cannot simply write-protect the fuses in place, because that would leave a valid key on esp32 devices with a known value of 0!) But we *first* have to burn in secure boot, because that also uses block key fuses. Watch this space.

Now, we have these perfectly random encryption keys, secured in our... host-readable efuses. Oh no. In fact, for secure boot, we *must* have this read-protected. We also don't want an attacker to overwrite them, which while not as bad, is still bad. Let's read- and write-disable now, via efuse:
```zsh
espefuse read_protect_efuse BLOCK_KEY0
espefuse read_protect_efuse BLOCK_KEY1
espefuse write_protect_efuse BLOCK_KEY0
espefuse write_protect_efuse BLOCK_KEY1
```

⚠️ We must also set a few others to prevent certain side-channel attacks:
```zsh
# we're not debugging these
espefuse burn_efuse DISABLE_DL_ENCRYPT 1
espefuse burn_efuse DISABLE_DL_DECRYPT 1
espefuse burn_efuse DISABLE_DL_CACHE 1
# optional for JTAG! if you use JTAG, don't burn this!
espefuse burn_efuse JTAG_DISABLE 1

# and write-protect them:
espefuse write_protect_efuse DIS_CACHE
```
### Secure Boot
Again, our first step is to generate our signing keys. ECDSA and RSA-3072 are supported. ECDSA, however, has a 2ms boot delay (with accompanying power draw!), while the RSA-3072 has a boot delay of 200us. I've chosen RSA-3072 for my application, however, `openssl` can generate either. Key generation is below:
```zsh
openssl genrsa -out my_secure_boot_signing_key.pem 3072
```
Build your program as normal, then sign:
```zsh
# sign
idf.py secure-sign-data --keyfile ./my_secure_boot_signing_key.pem --output ./image-signed.bin --input $UNSIGNED_IMAGE
# and verify
idf.py secure-verify-signature --keyfile ./my_secure_boot_signing_key.pem ./image_signed.bin
```

 We should now set up the esp32 device to read a signed bootloader. RSA is asymmetric encryption, meaning the public key to decrypt the data can be freely shared, but doesn't allow anyone to encrypt new data. The board uses two efuses to set the encrypted flash digest, starting at `BLOCK_KEY2` (since encrypted flash takes `BLOCK_KEY0` and `BLOCK_KEY1`). We **cannot** set global `RD_DIS`, because `BLOCK_KEY2` and `BLOCK_KEY3` need to be readable by software for secure boot!

This time the in-built tooling does what we want safely and sanely, so we can set this in an sdkconfig file:
```ini
# secure boot via RSA
CONFIG_SECURE_BOOT=y  
CONFIG_SECURE_BOOT_V2_ENABLED=y  
CONFIG_SECURE_BOOT_V2_RSA_ENABLED=y  
CONFIG_SECURE_SIGNED_APPS_RSA_SCHEME=y
CONFIG_SECURE_BOOT_BUILD_SIGNED_BINARIES=y
# stage 1 bootloader needs to load encrypted flash (see above)
CONFIG_SECURE_BOOT_FLASH_BOOTLOADER_DEFAULT=y
# and a few settings to ensure we can still flash new images:
CONFIG_SECURE_INSECURE_ALLOW_DL_MODE=y
CONFIG_SECURE_BOOT_INSECURE=  
CONFIG_SECURE_BOOT_ALLOW_JTAG=
CONFIG_SECURE_BOOT_V2_ALLOW_EFUSE_RD_DIS=
# if you turn this on, and accidentally flash the wrong image at any point,
# you have bricked your board.
CONFIG_SECURE_BOOT_ENABLE_AGGRESSIVE_KEY_REVOKE=

# ...

## put your actual config partition table and other stuff here
```
Now, we flash:
```zsh
idf.py encrypted-flash
```
And if all is successful, your board should flash its own efuses, crash, restart itself, and come up well. You can check the status of `SECURE_BOOT_EN` with `espefuse.py summary | grep SECURE`.

When this is done, we write-protect the digest and its purpose:
```zsh
espefuse write_protect_efuse BLOCK_KEY2
espefuse write_protect_efuse BLOCK_KEY3
espefuse write_protect_efuse KEY_PURPOSE_2
espefuse write_protect_efuse KEY_PURPOSE_3
```

## Locking Down the Last
⚠️ We have one remaining key efuse block, `BLOCK_KEY4`, which can be used to write an alternative signing key. Let's make it user-defined, so we don't allow it to be used for encryption
```zsh
espefuse burn_key_purpose BLOCK_KEY4 USER # writes to KEY_PURPOSE_4
espefuse write_protect_efuse KEY_PURPOSE_4 # and now we write-protect that
```

## So what did we do?
By following the steps above, we now have ~~a bunch of efuses and a weird config block~~
a robust and secure esp32 that can only have its flash written with the given key and its bootloader updated with the given signing key, and no way for a user to read or change either the signing or boot key. However, we can still reflash it given the keys and standard tools. This is great for on-site devices that may need additional updates but don't need the complexity (or additional security risks) of an OTA procedure.

### References
[Expressif SecureBoot v2 Documentation](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/security/secure-boot-v2.html)
[Expressif Encrypted Flash Documentation]()
[Expressif S3 Technical Reference Manual](https://documentation.espressif.com/esp32-s3_technical_reference_manual_en.pdf#extmemencr)
[Expressif Fuse Table](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/system/efuse.html)
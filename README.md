# StandaloneTime

StandaloneTime keeps a Logitech Squeezebox Radio's Linux system clock and
hardware RTC synchronized using internet time, without requiring LMS.

It is a headless SqueezePlay applet. It starts automatically through normal
service registration and changes no stock SqueezePlay files.

## Architecture

```
boot
  |
  v
MSP430 RTC -> Linux system clock
                  |
            Wi-Fi available
                  |
                  v
            StandaloneTime
                  |
                 SNTP
                  |
                  v
              correct UTC
                  |
             date -u -s
                  |
             hwclock -w -u
                  |
                  v
              MSP430 RTC
```

StandaloneTime synchronizes UTC only. Timezone and DST presentation remain
handled by SqueezePlay. No LMS or external Raspberry Pi/server is required;
the Radio needs internet access to an NTP server. After synchronization, the
hardware RTC retains time across reboot and the applet resynchronizes every 24
hours to compensate for drift.

The implementation has been physically tested on a Logitech Squeezebox Radio
running stock SqueezePlay firmware. Other Squeezebox models are not claimed.

## Installation

The primary installation route is the normal SqueezePlay Applet Installer:

1. Add `http://49.12.198.91/sbstandalone/extensions.xml` as an additional LMS
   repository.
2. Open `Settings -> Advanced -> Applet Installer` on the Radio.
3. Select `StandaloneTime` and choose `Install`.
4. Allow SqueezePlay to restart.

The package is headless; no menu interaction is required after installation.
The ZIP can also be deployed manually for development using the SSH/SCP
procedure documented by the project.

To uninstall, select `StandaloneTime` in Applet Installer and choose
`Remove`. This removes only the applet files. It does not reset the Linux
clock, erase the RTC, change timezone settings, or affect other applets.

## Diagnostics

```sh
date -u
hwclock -r -u
cat /proc/driver/rtc
grep StandaloneTime /var/log/messages
```

On the physically tested Radio firmware, `hwclock -r -u` applies the configured
local-time display conversion even though `/proc/driver/rtc` contains the raw
RTC value. For an unambiguous UTC check, compare `date -u` with
`/proc/driver/rtc` (or use `hwclock -r` on this firmware) and the
`StandaloneTime` synchronization log.

Successful synchronization includes messages similar to:

```text
StandaloneTime: valid SNTP response from time.google.com
StandaloneTime: UTC = 2026-09-28 11:53:17
StandaloneTime: date -u -s succeeded; writing RTC
StandaloneTime: hwclock -w -u succeeded
StandaloneTime: Linux clock and RTC synchronized from NTP UTC = 2026-09-28 11:53:17
```

The applet uses asynchronous BusyBox `nslookup` and UDP, which is compatible
with the stock Radio firmware's unreliable Lua DNS resolver. It tries an
ordered list of public NTP hostnames, applies bounded retry backoff after
failures, and does not depend on the Radio's current wall clock when deriving
the received UTC value.

# Changelog

## 0.2.0

- Use the proven asynchronous BusyBox `nslookup` resolver workaround for
  stock SqueezePlay firmware.
- Fix retry and 24-hour resynchronization scheduling to restart at the first
  configured NTP server.

## 0.1.0

- Initial release.
- Headless automatic startup through SqueezePlay service registration.
- Asynchronous DNS and `jive.net.SocketUdp` SNTP synchronization.
- Multiple NTP server fallback with timeout and retry backoff.
- 24-hour resynchronization.
- Linux system-clock update and MSP430 RTC persistence.
- No LMS dependency.
- Compatible with the physically tested ARMv5/SqueezePlay Radio runtime.

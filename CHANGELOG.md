# Changelog

## 0.1.0

- Initial release.
- Headless automatic startup through SqueezePlay service registration.
- Asynchronous DNS and `jive.net.SocketUdp` SNTP synchronization.
- Multiple NTP server fallback with timeout and retry backoff.
- 24-hour resynchronization.
- Linux system-clock update and MSP430 RTC persistence.
- No LMS dependency.
- Compatible with the physically tested ARMv5/SqueezePlay Radio runtime.

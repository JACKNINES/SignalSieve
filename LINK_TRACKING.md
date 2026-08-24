# Offline link tracking coverage

Signal Sieve analyzes the copied URL string only. It never opens a destination,
follows a redirect, downloads a page, or calls a platform API. A result therefore
uses one of four treatments:

- **Removed:** a verified tracking or share-attribution parameter was removed.
- **Detected but not resolvable offline:** the host or path is an opaque redirect;
  the URL remains unchanged because resolving it would require network contact.
- **Preserved because it may be functional:** an unrecognized or functional query
  parameter remains intact.
- **Outside clipboard scope:** pixels, cookies, device fingerprinting,
  server-side APIs, and in-app telemetry are named as limitations, not analyzed.

## Coverage matrix

| Platform | Offline coverage | Platform-specific handling |
| --- | --- | --- |
| Facebook | Strong | Share parameters and embedded `l.facebook.com/l.php` destination |
| YouTube | Strong | `si`, `feature`, and `pp`; video IDs remain intact |
| WhatsApp | Universal | Verified universal query parameters only |
| Instagram | Strong | `igsh`/`igshid` and canonical post/reel paths |
| TikTok | Strong | Host-scoped share parameters and canonical video paths |
| WeChat | Universal | Verified universal query parameters only |
| Reddit | Targeted | `rdt_cid`, scoped share parameters, `redd.it` and `/s/` detection |
| X | Targeted | `twclid`, scoped `s`/`t`, and `t.co` detection |
| LinkedIn | Targeted | `li_fat_id`, scoped `rcm`/`trk`/`trackingId`, and `lnkd.in` detection |
| Telegram | Universal | Verified universal query parameters only |
| Snapchat | Targeted | `ScCid`/`sc_click_id` and `t.snapchat.com` detection |
| Pinterest | Targeted | `epik` and `pin.it` detection |
| Discord | Universal | Verified universal query parameters only |
| Douyin | Universal | Verified universal query parameters only |
| Threads | Targeted | Domain-scoped `xmt`; unrelated domains retain `xmt` |
| VK | Universal | Verified universal query parameters only |
| Tumblr | Universal | Verified universal query parameters only |
| Twitch | Universal | Verified universal query parameters only |
| Line | Universal | Verified universal query parameters only |
| 4chan | Universal | Verified universal query parameters only |

“Universal” is intentionally conservative: Signal Sieve makes no claim that it
can remove account metadata, telemetry, or tracking performed after a link is
opened.

## Evidence and regression fixtures

The rule set and production-shaped test URLs are grounded in first-party
documentation where available:

- Snapchat documents `ScCid` as its URL click ID:
  <https://developers.snap.com/marketing-api/Conversions-API/Parameters>
- Pinterest documents `epik` as the unique click identifier appended to a URL:
  <https://developers.pinterest.com/docs/track-conversions/track-conversions-in-the-api/>
- LinkedIn documents `li_fat_id` as a first-party conversion identifier:
  <https://www.linkedin.com/help/lms/answer/a476761>
- Reddit documents URL-carried click IDs for Conversions API attribution:
  <https://business.reddithelp.com/articles/Knowledge/Conversions-API>

Tests deliberately do not verify a short link by resolving it. They verify that
known opaque hosts and paths are reported, remain byte-for-byte unchanged, and
never pass through a network client. The quality gate also rejects in-process
network APIs in privacy-sensitive source code.

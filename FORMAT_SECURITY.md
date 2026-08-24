# Format inspection and cleaning security

Signal Sieve routes by byte signature before extension, parses bounded
structures, writes a new file, reopens it, reanalyzes it, and confirms the
source remained byte-for-byte unchanged. Unknown, malformed, signed, encrypted,
or ambiguously linked structures fail closed.

| Format | Structural inspection | Conservative cleaning |
| --- | --- | --- |
| WebP | RIFF `C2PA`, `EXIF`, `XMP ` chunks | Rebuild RIFF, clear EXIF/XMP VP8X flags, preserve image/animation/ICC chunks |
| AVIF, HEIC/HEIF | `ftyp`, top-level `jumb` and standardized C2PA/XMP UUID boxes | Remove only independently sized top-level metadata boxes |
| BMP | Header-declared boundary | Truncate only bytes after the validated declared file size |
| GIF | Comment, XMP, and `C2PA_GIF` application extensions | Remove those extensions; preserve image data and `NETSCAPE2.0` looping |
| TIFF/BigTIFF | Bounded IFD traversal; XMP, IPTC, MakerNote, EXIF/GPS pointers, C2PA tag 52545 | Direct payload tags can be zeroed; EXIF/GPS pointer graphs are refused rather than orphaned |
| XLSX, PPTX | OOXML property parts, custom XML, signatures | Remove property/custom parts and relationships; refuse signatures |
| EPUB | OCF mimetype/container, OPF meta, container metadata, embedded-image markers, signatures/encryption | Preserve required publication metadata; remove optional tracking metadata and clean safe embedded images; refuse signatures/encryption |

The analyzer reports a C2PA carrier but does not claim that its COSE signature,
certificate chain, asset hash, or revocation status is valid. Those require a
compatible cryptographic validator. Color profiles are retained because they
affect rendering and are not treated as tracking metadata by default.

Audio and video containers are intentionally outside Signal Sieve's current
scope: MP4, MOV, M4A, M4V, WAV, and MP3 are neither advertised nor routed to a
cleaner.

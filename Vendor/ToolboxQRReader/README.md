# ToolboxQRReader

Local, offline SPM package. Origin/hash/license and empty-content and unsupported-ECI patches: see ../../ThirdPartyNotices/ZXingCpp/README.md.

Sources are copied from core/src of the pinned archive: root headers and common .cpp except TextEncoder/MultiFormatWriter/ZXingC/ZXingCpp, qrcode excluding legacy writer .cpp, libzueci, librscpp. Version.h is generated for a QR-only reader. Writer public stub translation units provide upstream's disabled-writer functions; no encoder is enabled. libzueci uses ZUECI_EMBED_NO_TO_ECI. `-O2` is scoped to this local native target because unoptimized detector templates are too expensive for interactive image scans; it does not change app optimization settings. C++20.

manifest.json stores upstream hashes, generated header and patched hashes separately. No binary blobs/download at build time. Toolbox bridge source is original project code.

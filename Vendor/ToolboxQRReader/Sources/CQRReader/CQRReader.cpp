#include "CQRReader.h"
#include "Barcode.h"
#include "ReadBarcode.h"
#include "ReaderOptions.h"
#include <array>
#include <memory>
#include <new>

struct Record {
    TQRItem item{};
    std::vector<uint8_t> bytes;
    std::string text, version, correction, sequence;
};
struct TQRResults { int status = 0; std::vector<Record> items; };
extern "C" TQRResults *tqr_read(const uint8_t *gray, int width, int height, int stride) {
    auto results = std::unique_ptr<TQRResults>(new (std::nothrow) TQRResults);
    if (!results) return nullptr;
    try {
        if (!gray || width <= 0 || height <= 0 || width > 4096 || height > 4096 || stride < width) {
            results->status = 1; return results.release();
        }
        auto options = ZXing::ReaderOptions().formats(ZXing::BarcodeFormat::QRCodeModel2)
            .tryRotate(true).tryInvert(true).tryHarder(true).returnErrors(false)
            .maxNumberOfSymbols(101).textMode(ZXing::TextMode::Plain);
        auto image = ZXing::ImageView{gray, width, height, ZXing::ImageFormat::Lum, stride};
        auto codes = ZXing::ReadBarcodes(image, options);
        // Failed finder combinations on collages can exhaust the symbol budget before real codes.
        // Only if no valid symbol exists, run one bounded candidate pass for unreadable diagnostics.
        if (codes.empty()) codes = ZXing::ReadBarcodes(image, options.returnErrors(true).maxNumberOfSymbols(8));
        results->items.reserve(codes.size());
        for (auto &code : codes) {
            Record r;
            r.item.valid = code.isValid(); r.item.content_type = static_cast<int>(code.contentType());
            r.item.has_eci = code.hasECI(); r.item.sequence_index = code.sequenceIndex();
            r.item.sequence_count = code.sequenceSize(); r.item.mirrored = code.isMirrored(); r.item.inverted = code.isInverted();
            const auto &p = code.position();
            auto points = std::array{p.topLeft(), p.topRight(), p.bottomRight(), p.bottomLeft()};
            for (size_t n = 0; n < 4; ++n) { r.item.xy[n*2] = points[n].x; r.item.xy[n*2+1] = points[n].y; }
            if (code.isValid()) {
                r.bytes = code.bytes();
                // Length-aware std::string, including embedded zero. Never use a C string for text.
                r.text = code.text(ZXing::TextMode::Plain);
            }
            r.version = code.extra(ZXing::BarcodeExtra::Version);
            r.correction = code.extra(ZXing::BarcodeExtra::ECLevel); r.sequence = code.sequenceId();
            results->items.push_back(std::move(r));
        }
    } catch (const std::bad_alloc&) { results->items.clear(); results->status = 2; }
      catch (...) { results->items.clear(); results->status = 1; }
    return results.release();
}
extern "C" int tqr_status(const TQRResults *r) { return r ? r->status : 2; }
extern "C" size_t tqr_count(const TQRResults *r) { return r ? r->items.size() : 0; }
extern "C" TQRItem tqr_item(const TQRResults *r, size_t i) {
    if (!r || i >= r->items.size()) return {};
    const auto &v = r->items[i]; auto item = v.item;
    item.bytes = v.bytes.data(); item.bytes_count = v.bytes.size();
    item.text = reinterpret_cast<const uint8_t *>(v.text.data()); item.text_count = v.text.size();
    item.version = v.version.c_str(); item.correction = v.correction.c_str(); item.sequence_id = v.sequence.c_str();
    return item;
}
extern "C" void tqr_free(TQRResults *r) { delete r; }

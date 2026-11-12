#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct TQRResults TQRResults;
typedef struct {
    int valid, content_type, has_eci, sequence_index, sequence_count, mirrored, inverted;
    double xy[8];
    const uint8_t *bytes, *text;
    size_t bytes_count, text_count;
    const char *version, *correction, *sequence_id;
} TQRItem;
// All pointers are owned by TQRResults until tqr_free; no C++ exception crosses this API.
TQRResults *tqr_read(const uint8_t *gray, int width, int height, int stride);
int tqr_status(const TQRResults *results); // 0 success, 1 invalid input/engine, 2 allocation
size_t tqr_count(const TQRResults *results);
TQRItem tqr_item(const TQRResults *results, size_t index);
void tqr_free(TQRResults *results);
#ifdef __cplusplus
}
#endif

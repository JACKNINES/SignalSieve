// SPDX-License-Identifier: MPL-2.0
#include "CSignalSieveZip.h"

#include <limits.h>
#include <string.h>
#include <zlib.h>

int ss_inflate_raw(
    const uint8_t *input,
    size_t input_size,
    uint8_t *output,
    size_t output_capacity,
    size_t *written
) {
    if (input == NULL || output == NULL || written == NULL
        || input_size > UINT_MAX || output_capacity > UINT_MAX) {
        return Z_STREAM_ERROR;
    }

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_size;
    stream.next_out = output;
    stream.avail_out = (uInt)output_capacity;

    int status = inflateInit2(&stream, -MAX_WBITS);
    if (status != Z_OK) {
        return status;
    }
    status = inflate(&stream, Z_FINISH);
    *written = (size_t)stream.total_out;
    inflateEnd(&stream);
    return status == Z_STREAM_END ? Z_OK : status;
}

// SPDX-License-Identifier: MPL-2.0
#ifndef C_SIGNALSIEVE_ZIP_H
#define C_SIGNALSIEVE_ZIP_H

#include <stddef.h>
#include <stdint.h>

int ss_inflate_raw(
    const uint8_t *input,
    size_t input_size,
    uint8_t *output,
    size_t output_capacity,
    size_t *written
);

#endif

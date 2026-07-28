def pack_fields(values, width):
    """Pack index-zero-first scalar values into one HDL vector."""
    packed = 0
    mask = (1 << width) - 1
    for index, value in enumerate(values):
        packed |= (value & mask) << (index * width)
    return packed


def unpack_field(packed, index, width):
    """Extract one index-zero-first scalar from a packed HDL vector."""
    return (packed >> (index * width)) & ((1 << width) - 1)

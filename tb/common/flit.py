FLIT_HEAD = 0
FLIT_BODY = 1
FLIT_TAIL = 2
FLIT_HEADTAIL = 3

FLIT_W = 64
COORD_W = 2
PAYLOAD_W = 46


def make_flit(
    flit_type,
    dst_x,
    dst_y,
    *,
    src_x=0,
    src_y=0,
    pkt_len=1,
    payload=0,
):
    """Pack one flit according to noc_pkg.sv."""
    value = (flit_type & 0x3) << 62
    value |= (dst_x & 0x3) << 60
    value |= (dst_y & 0x3) << 58
    value |= (src_x & 0x3) << 56
    value |= (src_y & 0x3) << 54
    value |= (pkt_len & 0xFF) << 46
    value |= payload & ((1 << PAYLOAD_W) - 1)
    return value

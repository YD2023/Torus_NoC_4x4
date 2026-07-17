package noc_pkg;
  parameter int NOC_X_DIM = 4;
  parameter int NOC_Y_DIM = 4;
  parameter int NOC_NUM_NODES = NOC_X_DIM * NOC_Y_DIM;
  parameter int NOC_NUM_PORTS = 5;
  parameter int NOC_NUM_VCS = 2;
  parameter int NOC_FLIT_W = 64;
  parameter int NOC_COORD_W = 2;
  parameter int NOC_PKT_LEN_W = 8;
  parameter int NOC_VC_W = 1;
  parameter int NOC_PAYLOAD_W = 46;

  typedef enum logic [1:0] {
    FLIT_HEAD     = 2'b00,
    FLIT_BODY     = 2'b01,
    FLIT_TAIL     = 2'b10,
    FLIT_HEADTAIL = 2'b11
  } flit_type_e;

  typedef enum logic [2:0] {
    PORT_NORTH = 3'd0,
    PORT_SOUTH = 3'd1,
    PORT_EAST  = 3'd2,
    PORT_WEST  = 3'd3,
    PORT_LOCAL = 3'd4
  } port_id_e;

  typedef enum logic [0:0] {
    VC0 = 1'b0,
    VC1 = 1'b1
  } vc_id_e;

  typedef struct packed {
    flit_type_e                         flit_type;
    logic [NOC_COORD_W-1:0]             dst_x;
    logic [NOC_COORD_W-1:0]             dst_y;
    logic [NOC_COORD_W-1:0]             src_x;
    logic [NOC_COORD_W-1:0]             src_y;
    logic [NOC_PKT_LEN_W-1:0]           pkt_len;
    logic [NOC_PAYLOAD_W-1:0]           payload;
  } flit_t;

  localparam int FLIT_TYPE_MSB = NOC_FLIT_W - 1;
  localparam int FLIT_TYPE_LSB = NOC_FLIT_W - 2;
  localparam int DST_X_MSB     = NOC_FLIT_W - 3;
  localparam int DST_X_LSB     = NOC_FLIT_W - 4;
  localparam int DST_Y_MSB     = NOC_FLIT_W - 5;
  localparam int DST_Y_LSB     = NOC_FLIT_W - 6;
  localparam int SRC_X_MSB     = NOC_FLIT_W - 7;
  localparam int SRC_X_LSB     = NOC_FLIT_W - 8;
  localparam int SRC_Y_MSB     = NOC_FLIT_W - 9;
  localparam int SRC_Y_LSB     = NOC_FLIT_W - 10;
  localparam int PKT_LEN_MSB   = NOC_FLIT_W - 11;
  localparam int PKT_LEN_LSB   = NOC_FLIT_W - 18;
  localparam int PAYLOAD_MSB   = NOC_FLIT_W - 19;
  localparam int PAYLOAD_LSB   = 0;
endpackage

import noc_pkg::*;

interface noc_link_if #(
  parameter int FLIT_W = noc_pkg::NOC_FLIT_W,
  parameter int VC_W   = noc_pkg::NOC_VC_W
);
  logic              valid;
  logic              ready;
  logic [FLIT_W-1:0] flit;
  logic [VC_W-1:0]   vc_id;

  modport source (
    output valid,
    input  ready,
    output flit,
    output vc_id
  );

  modport sink (
    input  valid,
    output ready,
    input  flit,
    input  vc_id
  );

  modport monitor (
    input valid,
    input ready,
    input flit,
    input vc_id
  );
endinterface

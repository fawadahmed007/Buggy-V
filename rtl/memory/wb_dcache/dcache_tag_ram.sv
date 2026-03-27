

`ifndef VERILATOR
`include "../../defines/cache_defs.svh"
`else
`include "cache_defs.svh"
`endif

module dcache_tag_ram
#(
parameter NUM_COL    = 4,
parameter COL_WIDTH  = 8,
parameter ADDR_WIDTH = $clog2(DCACHE_NO_OF_SETS), // 10, 
parameter DATA_WIDTH = NUM_COL*COL_WIDTH          // Data Width in bits
) (
  input wire                     clk,
  input wire                     rst_n,

  input wire                     req,
  input wire   [NUM_COL-1:0]     wr_en, 
  input wire   [ADDR_WIDTH-1:0]  addr,
  input wire   [DATA_WIDTH-1:0]  wdata,
  input wire			 dcache_flush,
  output logic [DATA_WIDTH-1:0]  rdata
);


// Memory
reg [DATA_WIDTH-1:0]             dcache_tagram[DCACHE_NO_OF_SETS-1:0];


generate
genvar i;

    for (i=0; i < NUM_COL; i++) begin
        always_ff @(posedge clk) begin
          //  if (en_a) begin
                if (wr_en[i]) begin
                    dcache_tagram[addr][i*COL_WIDTH +: COL_WIDTH] <= wdata[i*COL_WIDTH +: COL_WIDTH];
                    rdata[i*COL_WIDTH +: COL_WIDTH]               <= wdata[i*COL_WIDTH +: COL_WIDTH];
                end else begin
                    rdata[i*COL_WIDTH +: COL_WIDTH]               <= dcache_tagram[addr][i*COL_WIDTH +: COL_WIDTH];
                end
                if (dcache_flush) begin
                     dcache_tagram[addr][23] <= 0;
                end
         //   end
        end
    end
endgenerate

endmodule 

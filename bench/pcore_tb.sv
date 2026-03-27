`timescale 1 ns / 100 ps
`include "pcore_interface_defs.svh"

module pcore_tb(input bit clk, input bit reset);

reg                       irq_ext;
reg                       irq_soft;
reg                       uart_rx;
wire                      uart_tx;
logic                     spi_clk, spi_cs, spi_mosi, spi_miso;
reg [1023:0]              firmware;
reg [1023:0]              max_cycles = 100000;
reg [1023:0]              main_time  = '0;

soc_top dut (
  .clk                     (clk),
  .rst_n                   (reset),
  .irq_ext_i               (irq_ext),
  .irq_soft_i              (irq_soft),
  .uart_rxd_i              (uart_rx),
  .uart_txd_o              (uart_tx),
  .spi_clk_o               (spi_clk),
  .spi_cs_o                (spi_cs),
  .spi_miso_i              (spi_miso),
  .spi_mosi_o              (spi_mosi)
);

localparam logic [31:0] ACT4_SIGNATURE_ADDR = 32'hA000_0000;
localparam logic [31:0] ACT4_HALT_ADDR      = 32'hA000_0004;
localparam logic [31:0] ACT4_PASS           = 32'h0000_0001;
localparam logic [31:0] ACT4_FAIL           = 32'h0000_0002;

wire dbus_wr  = dut.dbus2peri.req && dut.dbus2peri.w_en;
wire sig_en   = dbus_wr && (dut.dbus2peri.addr == ACT4_SIGNATURE_ADDR);
wire halt_en  = dbus_wr && (dut.dbus2peri.addr == ACT4_HALT_ADDR);

integer write_sig = 0;

initial begin
  irq_ext   = 0;
  irq_soft  = 0;
  uart_rx   = 1;
  spi_miso  = 1;

  if($value$plusargs("imem=%s", firmware)) begin
    $display("Loading Instruction Memory from %0s", firmware);
    $readmemh(firmware, dut.mem_top_module.main_mem_module.dualport_memory);
  end else begin
    $error("Missing +imem=<hex file> plusarg");
    $finish;
  end

  if($value$plusargs("max_cycles=%d", max_cycles))
    $display("Timeout set as %0d cycles", max_cycles);
  else
    $display("Using default timeout = %0d cycles", max_cycles);

`ifdef COMPLIANCE
  write_sig = $fopen("DUT-pcore.signature", "w");
  if (write_sig == 0) begin
    $error("Error opening DUT-pcore.signature for writing");
    $finish;
  end
`endif
end

always_ff @(posedge clk) begin
  if (main_time < max_cycles) begin
    main_time <= main_time + 1;
  end else begin
    $display("Timeout: Exiting after %0d cycles", main_time);
`ifdef COMPLIANCE
    if (write_sig != 0) $fclose(write_sig);
`endif
    $finish;
  end
end

`ifdef COMPLIANCE
always_ff @(posedge clk) begin
  if (sig_en && (write_sig != 0)) begin
    $fwrite(write_sig, "%08h\n", dut.dbus2peri.w_data[31:0]);
  end else if (halt_en) begin
    if (write_sig != 0) $fclose(write_sig);
    case (dut.dbus2peri.w_data[31:0])
      ACT4_PASS: begin
        $display("ACT4 TEST PASS");
        $finish;
      end
      ACT4_FAIL: begin
        $error("ACT4 TEST FAIL");
        $finish;
      end
      default: begin
        $error("ACT4 TEST HALT with unknown status: %08h", dut.dbus2peri.w_data[31:0]);
        $finish;
      end
    endcase
  end
end
`endif

endmodule


`ifndef VERILATOR
`include "../../defines/pcore_interface_defs.svh"
`else
`include "pcore_interface_defs.svh"
`endif

module decode (

    input   logic                             rst_n,                  // reset
    input   logic                             clk,                    // clock

    // Fetch <---> Decode interface
    input wire type_if2id_data_s              if2id_data_i,
    input wire type_if2id_ctrl_s              if2id_ctrl_i,

    // Decode <---> Execute interface
    output type_id2exe_data_s                 id2exe_data_o,
    output type_id2exe_ctrl_s                 id2exe_ctrl_o,          // Structure for control signals  

    // CSR <---> Decode feedback interface
    input wire type_csr2id_fb_s               csr2id_fb_i,

    // Writeback <---> Decode feedback interface
    input wire type_wrb2id_fb_s               wrb2id_fb_i

  //  input wire type_debug_port_s              debug_port_i
);

//============================= Local signals and their assignments =============================//
// Local signals
logic [`RF_AWIDTH-1:0]               id2rf_rs1_addr;            // RF rs1 address
logic [`RF_AWIDTH-1:0]               id2rf_rs2_addr;            // RF rs2 address
//logic [`RF_AWIDTH-1:0]               id2exe_rd_addr;            // RF rd address

logic [`XLEN-1:0]                    instr_codeword;
logic [`XLEN-1:0]                    rf2id_rs1_data;            // RF rs1 data
logic [`XLEN-1:0]                    rf2id_rs2_data;            // RF rs2 data

// 
logic                                illegal_instr;

logic [2:0]                          funct3_opcode;
logic [6:0]                          funct7_opcode;
logic [4:0]                          funct5_opcode;
logic [4:0]                          shift_amt;

// Control and data signal structures
type_if2id_ctrl_s                    if2id_ctrl;
type_if2id_data_s                    if2id_data;
type_id2exe_ctrl_s                   id2exe_ctrl;
type_id2exe_data_s                   id2exe_data;

type_csr2id_fb_s                     csr2id_fb;
type_rv_opcode_e                     instr_opcode;

// Input signal assigments
assign if2id_ctrl = if2id_ctrl_i;
assign if2id_data = if2id_data_i;
assign csr2id_fb  = csr2id_fb_i;

// Instruction opcodes
assign instr_codeword = if2id_data.instr;
assign instr_opcode   = type_rv_opcode_e'(instr_codeword[6:2]); 
assign funct7_opcode  = instr_codeword[31:25];
assign funct3_opcode  = instr_codeword[14:12];
assign funct5_opcode  = instr_codeword[24:20];

// Register file related decodings
assign id2rf_rs1_addr = instr_codeword[19:15];
assign id2rf_rs2_addr = instr_codeword[24:20];
//assign id2exe_rd_addr = instr_codeword[11:7];

assign shift_amt      = instr_codeword[24:20]; 

//========================== Decoder logic implementation for control signals ==========================//
always_comb begin

    // Define decoder logic for control signals and prepare datapath signals for
    // execution phase. Set to default values for control signals when decoding 
    // an instruction.  
 
    // Operation selecion for different modules
    id2exe_ctrl.alu_i_ops  = ALU_I_OPS_NONE;
    id2exe_ctrl.alu_m_ops  = ALU_M_OPS_NONE;
    id2exe_ctrl.alu_b_ops  = ALU_B_OPS_NONE;
    id2exe_ctrl.alu_d_ops  = ALU_D_OPS_NONE;
    id2exe_ctrl.ld_ops     = LD_OPS_NONE;
    id2exe_ctrl.st_ops     = ST_OPS_NONE;
    id2exe_ctrl.branch_ops = BR_OPS_NONE;
    id2exe_ctrl.csr_ops    = CSR_OPS_NONE;
    id2exe_ctrl.amo_ops    = AMO_OPS_NONE;
    id2exe_ctrl.sys_ops    = SYS_OPS_NONE;

    // Operand selection for different modules
    id2exe_ctrl.alu_opr1_sel     = ALU_OPR1_PC;
    id2exe_ctrl.alu_opr2_sel     = ALU_OPR2_IMM;
    id2exe_ctrl.alu_cmp_opr2_sel = ALU_CMP_OPR2_REG;
    id2exe_ctrl.csr_opr_sel      = CSR_OPR_REG;
    id2exe_ctrl.rd_wrb_sel       = RD_WRB_NONE;
    id2exe_ctrl.rd_wr_req        = 1'b0;
    id2exe_ctrl.jump_req         = 1'b0;
    id2exe_ctrl.branch_req       = 1'b0;
    id2exe_ctrl.exc_req          = 1'b0;
    id2exe_ctrl.fence_i_req      = 1'b0;
    id2exe_ctrl.fence_req        = 1'b0;

    // Default values for datapath signals
    id2exe_data.imm      = {{21{instr_codeword[31]}}, instr_codeword[30:20]};
    id2exe_data.rs1_data = rf2id_rs1_data;   // These operands need to be updated in case of forwarding
    id2exe_data.rs2_data = rf2id_rs2_data;   // These operands need to be updated in case of forwarding
    id2exe_data.instr    = instr_codeword;
    id2exe_data.pc       = if2id_data.pc;
    id2exe_data.pc_next  = if2id_data.pc_next;
    id2exe_data.exc_code = EXC_CODE_NO_EXCEPTION;
    id2exe_data.instr_flushed = if2id_data.instr_flushed;
    
    // Default values for local signals
    illegal_instr       = 1'b0;

    // Check for instruction memory access fault
 /*   if (if2id_ctrl.exc_req) begin
        id2exe_ctrl.exc_req  = 1'b1;
        id2exe_data.exc_code = if2id_data.exc_code;    
        
    end else begin  // no instruction memory access fault
  */      case (instr_opcode)
            OPCODE_ARITH_INST  : begin
                
                id2exe_ctrl.rd_wrb_sel       = RD_WRB_ALU;
                id2exe_ctrl.alu_opr1_sel     = ALU_OPR1_REG;
                id2exe_ctrl.alu_opr2_sel     = ALU_OPR2_REG;
                id2exe_ctrl.alu_cmp_opr2_sel = ALU_CMP_OPR2_REG;
                id2exe_ctrl.rd_wr_req        = 1'b1;
                 case (funct7_opcode)
                    7'b0000000 : begin
                        case (funct3_opcode)
                            3'b000 : id2exe_ctrl.alu_i_ops = ALU_I_OPS_ADD;   // ADD
                            3'b001 : id2exe_ctrl.alu_i_ops = ALU_I_OPS_SLL;   // Shift Left Logical
                            3'b010 : id2exe_ctrl.alu_i_ops = ALU_I_OPS_SLT;   // Set Less Than
                            3'b011 : id2exe_ctrl.alu_i_ops = ALU_I_OPS_SLTU;  // Set Less Than Unsigned
                            3'b110 : id2exe_ctrl.alu_i_ops = ALU_I_OPS_XOR;   // XOR Logical
                            3'b101 : id2exe_ctrl.alu_i_ops = ALU_I_OPS_SRL;   // Shift Right Logical 
                            3'b100 : id2exe_ctrl.alu_i_ops = ALU_I_OPS_OR;    // OR Logical
                            3'b111 : id2exe_ctrl.alu_i_ops = ALU_I_OPS_AND;   // AND Logical
                        endcase // funct3_opcode
                    end // 7'b0000000
                    7'b0100000 : begin
                        case (funct3_opcode)
                            3'b000  : id2exe_ctrl.alu_i_ops = ALU_I_OPS_SUB;
                            3'b100  : id2exe_ctrl.alu_b_ops = ALU_ZBB_OPS_XNOR;
                            3'b101  : id2exe_ctrl.alu_i_ops = ALU_I_OPS_SRA;
                            3'b110  : id2exe_ctrl.alu_b_ops = ALU_ZBB_OPS_ORN;
                            3'b111  : id2exe_ctrl.alu_b_ops = ALU_ZBB_OPS_ANDN;
                            default : illegal_instr         = 1'b1;
                        endcase // funct3_opcode
                    end // 7'b0100000
                    7'b0010000: begin
                        case (funct3_opcode)
                            3'b010: id2exe_ctrl.alu_b_ops = ALU_ZBA_OPS_SH1ADD;
                            3'b100: id2exe_ctrl.alu_b_ops = ALU_ZBA_OPS_SH2ADD;
                            3'b110: id2exe_ctrl.alu_b_ops = ALU_ZBA_OPS_SH3ADD;
                            default : illegal_instr       = 1'b1;
                        endcase // funct3_opcode
                    end // 7'b0010000
                    7'b0000001 : begin
                        if (funct3_opcode[2]) begin
                            id2exe_ctrl.rd_wrb_sel = RD_WRB_D_ALU;
                        end
                        case (funct3_opcode)
                            3'b000 : id2exe_ctrl.alu_m_ops = ALU_M_OPS_MUL;
                            3'b001 : id2exe_ctrl.alu_m_ops = ALU_M_OPS_MULH;
                            3'b010 : id2exe_ctrl.alu_m_ops = ALU_M_OPS_MULHSU;
                            3'b011 : id2exe_ctrl.alu_m_ops = ALU_M_OPS_MULHU;

                            3'b100 : id2exe_ctrl.alu_d_ops = ALU_D_OPS_DIV;
                            3'b101 : id2exe_ctrl.alu_d_ops = ALU_D_OPS_DIVU;
                            3'b110 : id2exe_ctrl.alu_d_ops = ALU_D_OPS_REM;
                            3'b111 : id2exe_ctrl.alu_d_ops = ALU_D_OPS_REMU;
                        endcase // funct3_opcode
                    end // 7'b0000001
                    7'b0000101 : begin
                        case (funct3_opcode)
                            3'b001 : id2exe_ctrl.alu_b_ops = ALU_ZBC_OPS_CLMUL;
                            3'b010 : id2exe_ctrl.alu_b_ops = ALU_ZBC_OPS_CLMULR;
                            3'b011 : id2exe_ctrl.alu_b_ops = ALU_ZBC_OPS_CLMULH;
                            3'b100 : id2exe_ctrl.alu_b_ops = ALU_ZBB_OPS_MIN;
                            3'b101 : id2exe_ctrl.alu_b_ops = ALU_ZBB_OPS_MINU;
                            3'b110 : id2exe_ctrl.alu_b_ops = ALU_ZBB_OPS_MAX;
                            3'b111 : id2exe_ctrl.alu_b_ops = ALU_ZBB_OPS_MAXU;
                            default: illegal_instr         = 1'b1;
                        endcase
                    end // 7'b0000101
                    7'b0000100 : begin
                        id2exe_ctrl.alu_b_ops = ALU_ZBB_OPS_ZEXTH;
                    end
                    7'b0110000 : begin
                        case (funct3_opcode)
                            3'b001 : id2exe_ctrl.alu_b_ops = ALU_ZBB_OPS_ROL;
                            3'b101 : id2exe_ctrl.alu_b_ops = ALU_ZBB_OPS_ROR;
                            default: illegal_instr         = 1'b1;
                        endcase
                    end
                    7'b0100100 : begin
                        case (funct3_opcode)
                            3'b001 : id2exe_ctrl.alu_b_ops = ALU_ZBS_OPS_BCLR;
                            3'b101 : id2exe_ctrl.alu_b_ops = ALU_ZBS_OPS_BEXT;
                            default: illegal_instr         = 1'b1;
                        endcase
                    end
                    7'b0110100 : begin
                        id2exe_ctrl.alu_b_ops = ALU_ZBS_OPS_BINV;
                    end
                    7'b0010100 : begin
                        id2exe_ctrl.alu_b_ops = ALU_ZBS_OPS_BSET;
                    end
                    default : illegal_instr = 1'b1;
                endcase // funct7_opcode
               
            end // OPCODE_ARITH_INST

            // IMM operation
            OPCODE_IMM_INST : begin

                id2exe_ctrl.rd_wrb_sel       = RD_WRB_ALU;
                id2exe_ctrl.alu_opr1_sel     = ALU_OPR1_REG;
                id2exe_ctrl.alu_opr2_sel     = ALU_OPR2_IMM;
                id2exe_ctrl.alu_cmp_opr2_sel = ALU_CMP_OPR2_IMM;
                id2exe_ctrl.rd_wr_req        = 1'b1;
                case (funct3_opcode)
                    3'b000 : id2exe_ctrl.alu_i_ops = ALU_I_OPS_ADD;           // ADD Immediate
                    3'b010 : id2exe_ctrl.alu_i_ops = ALU_I_OPS_SLT;           // SLT Immediate
                    3'b011 : id2exe_ctrl.alu_i_ops = ALU_I_OPS_SLTU;          // SLTU Immediate 
                    3'b110 : id2exe_ctrl.alu_i_ops = ALU_I_OPS_XOR;           // XOR Immediate
                    3'b100 : id2exe_ctrl.alu_i_ops = ALU_I_OPS_OR;            // OR Immediate
                    3'b111 : id2exe_ctrl.alu_i_ops = ALU_I_OPS_AND;           // AND Immediate
                    3'b001 : begin
                        case (funct7_opcode)
                            7'b0000000: begin
                                id2exe_data.imm     = `XLEN'(shift_amt);     // Zero Extend the shift amount
                                id2exe_ctrl.alu_i_ops = ALU_I_OPS_SLL;           // Shift Left Logical Immediate
                            end
                            7'b0110000: begin
                                case (funct5_opcode)
                                    5'b00000 : begin
                                        id2exe_ctrl.alu_b_ops = ALU_ZBB_OPS_CLZ;
                                    end
                                    5'b00001 : begin
                                        id2exe_ctrl.alu_b_ops = ALU_ZBB_OPS_CTZ;
                                    end
                                    5'b00010 : begin
                                        id2exe_ctrl.alu_b_ops = ALU_ZBB_OPS_CPOP;
                                    end
                                    5'b00100 : begin
                                        id2exe_ctrl.alu_b_ops = ALU_ZBB_OPS_SEXTB;
                                    end

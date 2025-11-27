// `define SS_FACTOR 1
// `define SS_FACTOR_BITS $clog2(SS_FACTOR)
// `define NUM_PHYS_REGS 64
// `define NUM_PHYS_REGS_BITS $clog2(NUM_PHYS_REGS)
// `define NUM_RES_STATIONS 4
// `define RES_STATION_BITS $clog2(NUM_RES_STATIONS)
// `define NUM_ROB_ENTRIES 64
// `define NUM_ROB_ENTRIES_BITS $clog2(NUM_ROB_ENTRIES)
// `define NUM_FREE_LIST NUM_PHYS_REGS - 32
// `define NUM_FREE_LIST_BITS $clog2(NUM_FREE_LIST)
// `define NUM_CDB SS_FACTOR
// `define NUM_ISSUE 2
// `define NUM_MULT_UNITS 2
// `define NUM_ALU_CMP_UNITS 2

/////////////////////////////////////////////////////////////
//  Maybe use some of your types from mp_pipeline here?    //
//    Note you may not need to use your stage structs      //
/////////////////////////////////////////////////////////////

package rv32i_types;
    localparam int unsigned NUM_RS_FU_GROUPS = 4;
    localparam NUM_ALU_GROUP = 2;
    localparam NUM_MULT_GROUP = 1;
    localparam NUM_RS_GROUP = 4;
    localparam NUM_RES_STATIONS = NUM_RS_FU_GROUPS * NUM_RS_GROUP;
    localparam NUM_ALU_CMP_UNITS = NUM_RS_FU_GROUPS * NUM_ALU_GROUP;
    localparam NUM_MULT_UNITS = NUM_RS_FU_GROUPS * NUM_MULT_GROUP;
    localparam NUM_ALU_ISSUE_GROUP = (NUM_ALU_GROUP < NUM_RS_GROUP) ? NUM_ALU_GROUP : NUM_RS_GROUP;
    localparam NUM_MULT_ISSUE_GROUP = (NUM_MULT_GROUP < NUM_RS_GROUP) ? NUM_MULT_GROUP : NUM_RS_GROUP;
    localparam NUM_ALU_MULT_ISSUE_GROUP = NUM_ALU_ISSUE_GROUP + NUM_MULT_ISSUE_GROUP;
    localparam NUM_ALU_MULT_ISSUE = NUM_RS_FU_GROUPS * NUM_ALU_MULT_ISSUE_GROUP;
    localparam NUM_ALU_PER_CDB = 2;
    localparam NUM_MULT_PER_CDB = 4;
    localparam NUM_ALU_CDB = NUM_ALU_CMP_UNITS / NUM_ALU_PER_CDB;
    localparam NUM_MULT_CDB = NUM_MULT_UNITS / NUM_MULT_PER_CDB;
    localparam NUM_ALU_MULT_CDB = NUM_ALU_CDB + NUM_MULT_CDB;
    
    localparam MAX_BIT_COUNT = 8; // used for rename_dispatch stuff
    localparam SS_FACTOR = 2;
    localparam SS_FACTOR_BITS = $clog2(SS_FACTOR);
    localparam INSTR_FETCH_NUM = 2;
    localparam INSTR_FETCH_NUM_BITS = $clog2(INSTR_FETCH_NUM);
    localparam NUM_PHYS_REGS = 64;
    localparam NUM_PHYS_REGS_BITS = $clog2(NUM_PHYS_REGS);
    // localparam NUM_RES_STATIONS = 2;
    localparam RES_STATION_BITS = $clog2(NUM_RES_STATIONS);
    localparam NUM_ROB_ENTRIES = 64;
    localparam NUM_ROB_ENTRIES_BITS = $clog2(NUM_ROB_ENTRIES);
    localparam NUM_BRQ_ENTRIES = 16;
    localparam NUM_BRQ_ENTRIES_BITS = $clog2(NUM_BRQ_ENTRIES);
    localparam NUM_FREE_LIST = NUM_PHYS_REGS - 32;
    localparam NUM_FREE_LIST_BITS = $clog2(NUM_FREE_LIST);
    localparam NUM_LSQ_ENTRIES = 8; // now this will be number of store entries
    localparam NUM_LSQ_ENTRIES_BITS = $clog2(NUM_LSQ_ENTRIES);
    // localparam NUM_MULT_UNITS = 2;
    // localparam NUM_ALU_CMP_UNITS = 2;
    localparam INSTR_WIDTH = 32;
    localparam NUM_BRANCH = 16;
    localparam NUM_BRANCH_BITS = $clog2(NUM_BRANCH);
    // localparam NUM_ALU_MULT_ISSUE = 2;
    // localparam NUM_ALU_MULT_CDB = 1;
    localparam NUM_LD_ST_ISSUE = 1;
    localparam NUM_LD_ST_CDB = 1;
    localparam NUM_CDB = NUM_ALU_MULT_CDB + NUM_LD_ST_CDB;
    localparam NUM_ISSUE = NUM_ALU_MULT_ISSUE + NUM_LD_ST_ISSUE;

    localparam NUM_BR_PRED = 64;
    localparam NUM_BR_PRED_BITS = $clog2(NUM_BR_PRED);

    localparam NUM_LOAD_RS = 8;
    localparam LOAD_RS_BITS = $clog2(NUM_LOAD_RS);


    typedef logic [4:0] arch_reg;
    typedef logic [NUM_PHYS_REGS_BITS - 1:0] phys_reg;
    typedef logic [NUM_ROB_ENTRIES_BITS - 1:0] rob_num_t;

    // Add more things here . . .

    typedef enum bit [6:0] {
        op_lui   = 7'b0110111, // load upper immediate (U type)
        op_auipc = 7'b0010111, // add upper immediate PC (U type)
        op_jal   = 7'b1101111, // jump and link (J type)
        op_jalr  = 7'b1100111, // jump and link register (I type)
        op_br    = 7'b1100011, // branch (B type)
        op_load  = 7'b0000011, // load (I type)
        op_store = 7'b0100011, // store (S type)
        op_imm   = 7'b0010011, // arith ops with register/immediate operands (I type)
        op_reg   = 7'b0110011  // arith ops with register operands (R type)
    } rv32i_opcode;

    typedef enum bit [6:0] {
        mult = 7'b0000001
    } funct7_t;

    typedef enum bit [2:0] {
        beq  = 3'b000,
        bne  = 3'b001,
        blt  = 3'b100,
        bge  = 3'b101,
        bltu = 3'b110,
        bgeu = 3'b111
    } branch_funct3_t;

    typedef enum bit [2:0] {
        lb  = 3'b000,
        lh  = 3'b001,
        lw  = 3'b010,
        lbu = 3'b100,
        lhu = 3'b101
    } load_funct3_t;

    typedef enum bit [2:0] {
        sb = 3'b000,
        sh = 3'b001,
        sw = 3'b010
    } store_funct3_t;

    typedef enum bit [2:0] {
        add  = 3'b000, //check bit 30 for sub if op_reg opcode
        sll  = 3'b001,
        slt  = 3'b010,
        sltu = 3'b011,
        axor = 3'b100,
        sr   = 3'b101, //check bit 30 for logical/arithmetic
        aor  = 3'b110,
        aand = 3'b111
    } arith_funct3_t;

    typedef enum bit [2:0] {
        alu_add = 3'b000,
        alu_sll = 3'b001,
        alu_sra = 3'b010,
        alu_sub = 3'b011,
        alu_xor = 3'b100,
        alu_srl = 3'b101,
        alu_or  = 3'b110,
        alu_and = 3'b111
    } alu_ops;

    typedef enum bit [2:0] {
        mul = 3'b000,
        mulh = 3'b001,
        mulhsu = 3'b010,
        mulhu = 3'b011
    } mul_funct3_t;

    typedef enum bit [1:0] {
        unsigned_unsigned = 2'b00,
        signed_signed = 2'b01,
        signed_unsigned = 2'b10
    } mul_ops;

    typedef enum logic [1:0] {EMPTY, WAIT_FOR_STORE, WAIT_FOR_REG, READY} load_rs_state_t;

    typedef union packed {
        bit [31:0] word;

        struct packed {
        bit [11:0] i_imm;
        bit [4:0] rs1;
        bit [2:0] funct3;
        bit [4:0] rd;
        rv32i_opcode opcode;
        } i_type;

        struct packed {
        bit [6:0] funct7;
        bit [4:0] rs2;
        bit [4:0] rs1;
        bit [2:0] funct3;
        bit [4:0] rd;
        rv32i_opcode opcode;
        } r_type;

        struct packed {
        bit [11:5] imm_s_top;
        bit [4:0]  rs2;
        bit [4:0]  rs1;
        bit [2:0]  funct3;
        bit [4:0]  imm_s_bot;
        rv32i_opcode opcode;
        } s_type;
        
        struct packed {
            bit imm_b_12;
            bit [10:5] imm_b_midh;
            bit [4:0] rs2;
            bit [4:0] rs1;
            bit [2:0] funct3;
            bit [4:1] imm_b_midl;
            bit imm_b_11;
            rv32i_opcode opcode;
        } b_type;

        struct packed {
            bit [31:12] imm;
            bit [4:0] rd;
            rv32i_opcode opcode;
        } u_type;

        struct packed {
            bit [31:12] imm;
            bit [4:0]  rd;
            rv32i_opcode opcode;
        } j_type;

    } instr_t;
    
    typedef struct packed {
        logic valid;
        logic [31:0] pc;
        instr_t instruction;
        
        // for branch prediction
        logic br_taken_pred;
    } pc_instr_t;

    typedef struct packed {
        logic valid;
        logic [63:0] order;
        logic [31:0] inst;
        logic [4:0] rs1_s;
        logic [4:0] rs2_s;
        logic [31:0] rs1_v;
        logic [31:0] rs2_v;
        logic [4:0] rd_s;
        logic [31:0] rd_wdata;
        logic [31:0] pc_rdata;
        logic [31:0] pc_wdata;
        logic [31:0] mem_addr;
        logic [3:0] mem_rmask;
        logic [3:0] mem_wmask;
        logic [31:0] mem_rdata;
        logic [31:0] mem_wdata;
    } rvfi_data_t;

    typedef struct packed {
        logic busy;
        instr_t instr; 
        phys_reg ps1_s;
        phys_reg ps2_s;
        phys_reg pd_s;
        rob_num_t rob_num;
        rvfi_data_t rvfi_data;
        logic [31:0] pc;

        // for branch prediction
        logic br_taken_pred;
    } rs_entry_t;

    typedef struct packed {
        logic valid;
        phys_reg pd_s;
        rob_num_t rob_num;
        logic [31:0] pd_v;
        rvfi_data_t rvfi_data;
        logic br_en; // for backwards compatibility, this will be the bit indicating a mispredict has occurred
        logic [31:0] branch_pc;

        // inputs to the branch predictor
        logic [31:0] instr_pc;
        logic instr_is_br;
        logic br_taken;
    } cdb_t;

    typedef struct packed {
        logic start;
        phys_reg pd_s;
        rob_num_t rob_num;
        rvfi_data_t rvfi_data;
        logic [31:0] ps1_v;
        logic [31:0] ps2_v;
        
    } arbiter_fu_input_t; // don't think this is used anywhere
    

    typedef struct packed {
        logic valid;
        logic br;
        arch_reg arch_reg_d;
        phys_reg phys_reg_d;
        rvfi_data_t rvfi_data;
    } rob_entry_t;

    typedef struct packed {
        logic [31:0] branch_pc;
        logic [NUM_ROB_ENTRIES_BITS - 1 : 0] rob_idx;
    } brq_entry_t;

    typedef struct packed {
        instr_t instr;
        logic [31:0] ps1_v;
        logic [31:0] ps2_v;
        rvfi_data_t rvfi_data;
        rob_num_t rob_num;
        phys_reg pd_s;
        logic [31:0] pc;

        // for branch prediction
        logic br_taken_pred;
    } issue_fu_data_t;

    typedef struct packed {
        phys_reg pd_s;
        rob_num_t rob_num;
        logic [31:0] pd_v;
        rvfi_data_t rvfi_data;
        logic br_en;
        logic [31:0] br_target;

        // for branch prediction
        logic [31:0] instr_pc;
        logic instr_is_br;
        logic br_taken;
    } fu_cdb_data_t;

    typedef struct packed {
        phys_reg ps1_s;
        phys_reg ps2_s;
        phys_reg pd_s;
        rob_num_t rob_num;
        instr_t store_load_inst;
        rvfi_data_t rvfi_data;
    } lsq_entry_t;

    typedef struct packed {
        logic rs_valid;
        logic [$clog2(NUM_RS_GROUP) - 1 : 0] ready_rs_idx;
        logic fu_valid;
        logic [$clog2(NUM_ALU_GROUP) - 1 : 0] ready_fu_idx;
    } alu_issue_t;

    typedef struct packed {
        logic rs_valid;
        logic [$clog2(NUM_RS_GROUP) - 1 : 0] ready_rs_idx;
        logic fu_valid;
        logic [$clog2(NUM_MULT_GROUP) - 1 : 0] ready_fu_idx;
    } mult_issue_t;
    
    localparam PC_INSTR_T_BITS = unsigned'($bits(pc_instr_t));

    typedef struct packed {
        phys_reg ps1_s;
        phys_reg pd_s;
        rob_num_t rob_num;
        instr_t instr;
        rvfi_data_t rvfi_data;
        rob_num_t store_dependency;
        load_rs_state_t state;
    } load_rs_entry_t;

endpackage

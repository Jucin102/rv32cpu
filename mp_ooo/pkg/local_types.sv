parameter int NUM_MULT_UNITS = 2
parameter int NUM_ALU_CMP_UNITS = 2
typedef struct packed {
    instr_t instr;
    logic [31:0] ps1_v;
    logic [31:0] ps2_v;
    rvfi_data_t rvfi_data;
    rob_num_t rob_num;
    phys_reg pd_s;
    logic [31:0] pc;
} issue_fu_data_t;

typedef struct packed {
        phys_reg pd_s;
        rob_num_t rob_num;
        logic [31:0] pd_v;
        rvfi_data_t rvfi_data;
} fu_cdb_data_t;
typedef enum bit [6:0] {
    mult = 7'b0000001;
} funct7_t;

// add pc to rs_entry_t
// change NUM_ISSUE to 2

localparam NUM_RS_FU_GROUPS = 4;
localparam NUM_ALU_GROUP = 2;
localparam NUM_MULT_GROUP = 1;
localparam NUM_RS_GROUP = 4;
localparam NUM_ALU_CMP_UNITS = NUM_RS_FU_GROUPS * NUM_ALU_GROUP;
localparam NUM_MULT_UNITS = NUM_RS_FU_GROUPS * NUM_MULT_GROUP;
localparam NUM_ALU_ISSUE_GROUP = (NUM_ALU_GROUP < NUM_RS_GROUP) ? NUM_ALU_GROUP : NUM_RS_GROUP;
localparam NUM_MULT_ISSUE_GROUP = (NUM_MULT_GROUP < NUM_RS_GROUP) ? NUM_MULT_GROUP : NUM_RS_GROUP;
localparam NUM_ALU_MULT_ISSUE_GROUP = NUM_ALU_ISSUE_GROUP + NUM_MULT_ISSUE_GROUP;
localparam NUM_ALU_MULT_ISSUE = NUM_RS_FU_GROUPS * NUM_ALU_ISSUE_GROUP;

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
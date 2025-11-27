module cpu
import rv32i_types::*;
#(
    parameter WIDTH = 32,
    parameter SS = SS_FACTOR
)
(
    // Explicit dual port connections when caches are not integrated into design yet (Before CP3)
    input   logic           clk,
    input   logic           rst,

    // output  logic   [31:0]  imem_addr,
    // output  logic   [WIDTH / 8 - 1 : 0]   imem_rmask,
    // input   logic   [WIDTH - 1 : 0]  imem_rdata,
    // input   logic           imem_resp,

    // output  logic   [31:0]  dmem_addr,
    // output  logic   [3:0]   dmem_rmask,
    // output  logic   [3:0]   dmem_wmask,
    // input   logic   [31:0]  dmem_rdata,
    // output  logic   [31:0]  dmem_wdata,
    // input   logic           dmem_resp

    // input logic instr_queue_pop // remove later: this is used for testing with top_tb (cp1)
    // input logic cp1_instr_queue_push // remove later: this is used for testing with top_tb (cp1)

    // Single memory port connection when caches are integrated into design (CP3 and after)
    output logic   [31:0]      bmem_addr,
    output logic               bmem_read,
    output logic               bmem_write,
    output logic   [63:0]      bmem_wdata,
    input logic               bmem_ready,

    input logic   [31:0]      bmem_raddr,
    input logic   [63:0]      bmem_rdata,
    input logic               bmem_rvalid
    
);

    logic [INSTR_FETCH_NUM * ($bits(pc_instr_t)) - 1 : 0] instr_queue_output;
    logic [INSTR_FETCH_NUM * ($bits(pc_instr_t)) - 1 : 0] instr_queue_input;
    logic instr_queue_full, instr_queue_empty, instr_queue_push;
    logic instr_queue_pop;

    // SS parameter mainly used to determine # of ports
    // I/O rat <-> Dispatch
    // logic [SS_FACTOR_BITS : 0] rat_update;
    arch_reg rd_to_rat[SS];
    phys_reg pd_to_rat[SS];
    arch_reg rs1_to_rat[SS];
    arch_reg rs2_to_rat[SS];

    phys_reg ps1_to_dispatch[SS];
    phys_reg ps2_to_dispatch[SS];

    // I/O Free list <-> Dispatch
    phys_reg used_registers_to_dispatch[SS];
    logic [NUM_FREE_LIST_BITS : 0] num_free_regs_free_list;

    logic [SS_FACTOR_BITS : 0] free_list_pop;

    // I/O Free list <-> RRF
    logic [SS_FACTOR_BITS : 0] free_list_push;
    phys_reg old_phys_regs_to_free_list[SS];

    // I/O rob <-> Dispatch
    rob_entry_t rob_entries_to_rob[SS];
    logic [NUM_ROB_ENTRIES_BITS : 0] num_free_regs_rob;
    logic [NUM_ROB_ENTRIES_BITS - 1 : 0] rob_number_dispatch;
    logic [SS_FACTOR_BITS:0] rob_push;

    // I/O branch queue <-> Dispatch
    logic [NUM_BRQ_ENTRIES_BITS : 0] num_free_brq_entries;
    brq_entry_t brq_entry[SS];
    logic [SS_FACTOR_BITS : 0] brq_push; 

    // I/O branch queue <-> fetch
    brq_entry_t br_PC;

    // I/O rob <-> RRF
    logic [SS_FACTOR_BITS : 0]rrf_commit_cnt;
    arch_reg arch_reg_to_rrf[SS];
    phys_reg phys_reg_to_rrf[SS];

    // I/O Dispatch <-> Reservation Stations
    logic [NUM_RES_STATIONS-1:0] dispatch_rs_we;
    logic [NUM_RES_STATIONS-1:0] dispatch_rs_busy;
    rs_entry_t dispatch_rs_data[NUM_RES_STATIONS];
    
    // I/O Dispatch <-> Register File
    logic [SS_FACTOR - 1 : 0] invalidate_register_mask;
    phys_reg invalidate_registers [SS_FACTOR];

    // I/O Dispatch <-> LSQ
    logic [SS_FACTOR_BITS:0] lsq_dispatch_push;
    lsq_entry_t dispatch_store_load_input[SS];
    logic [NUM_LSQ_ENTRIES_BITS:0] lsq_free;

    // I/O Mem Arbiter <-> LSQ
    logic lsq_arbiter_pop;
    lsq_entry_t arbiter_store_load_output;
    logic lsq_empty;

    // I/O Issue Arbiter <-> reg file
    logic [NUM_PHYS_REGS - 1 : 0] reg_file_valid;
    phys_reg issue_reg_file_ps1_s [NUM_ALU_MULT_ISSUE];
    phys_reg issue_reg_file_ps2_s [NUM_ALU_MULT_ISSUE];
    logic [31:0] issue_reg_file_ps1_v [NUM_ALU_MULT_ISSUE];
    logic [31:0] issue_reg_file_ps2_v [NUM_ALU_MULT_ISSUE];

    // I/O mem arbiter <-> reg file
    phys_reg mem_issue_reg_file_ps1_s;
    phys_reg mem_issue_reg_file_ps2_s;
    logic [31:0] mem_issue_reg_file_ps1_v;
    logic [31:0] mem_issue_reg_file_ps2_v;

    // I/O reg file
    phys_reg reg_file_ps1_s [NUM_ALU_MULT_ISSUE + NUM_LD_ST_ISSUE];
    phys_reg reg_file_ps2_s [NUM_ALU_MULT_ISSUE + NUM_LD_ST_ISSUE];
    logic [31:0] reg_file_ps1_v [NUM_ALU_MULT_ISSUE + NUM_LD_ST_ISSUE];
    logic [31:0] reg_file_ps2_v [NUM_ALU_MULT_ISSUE + NUM_LD_ST_ISSUE];

    always_comb
    begin
        for(int unsigned i = 0; i < NUM_ALU_MULT_ISSUE; i++) begin
            reg_file_ps1_s[i] = issue_reg_file_ps1_s[i];
            reg_file_ps2_s[i] = issue_reg_file_ps2_s[i];
            issue_reg_file_ps1_v[i] = reg_file_ps1_v[i];
            issue_reg_file_ps2_v[i] = reg_file_ps2_v[i];
        end
        
        reg_file_ps1_s[NUM_ALU_MULT_ISSUE] = mem_issue_reg_file_ps1_s;
        reg_file_ps2_s[NUM_ALU_MULT_ISSUE] = mem_issue_reg_file_ps2_s;

        
        mem_issue_reg_file_ps1_v = reg_file_ps1_v[NUM_ALU_MULT_ISSUE];
        mem_issue_reg_file_ps2_v = reg_file_ps2_v[NUM_ALU_MULT_ISSUE];
    end
    
    // I/O Reservation Stations <-> Issue Arbiter
    rs_entry_t rs_issue_rs_curr[NUM_RES_STATIONS];
    logic [NUM_RES_STATIONS-1:0] rs_issue_to_free;

    // CDB bus
    cdb_t cdb[NUM_CDB];

    // CDB and no_ss_cdb_arbiter
    cdb_t cdb_alu_mul[NUM_ALU_MULT_CDB];

    // CDB and mem_arbiter
    cdb_t cdb_mem;

    always_comb
    begin
        for(int unsigned i = 0; i < NUM_ALU_MULT_CDB; i++) begin
            cdb[i] = cdb_alu_mul[i];
        end
        cdb[NUM_ALU_MULT_CDB] = cdb_mem;
    end

    // I/O Issue Arbiter <-> ALU/CMP Units
    issue_fu_data_t issue_alu_cmp_input_data[NUM_ALU_CMP_UNITS];
    logic [NUM_ALU_CMP_UNITS-1:0] issue_alu_cmp_fu_start;
    logic [NUM_ALU_CMP_UNITS-1:0] issue_alu_cmp_fu_busy; 

    // I/O Issue Arbiter <-> Mult Units
    issue_fu_data_t issue_mult_input_data[NUM_MULT_UNITS];
    logic [NUM_MULT_UNITS-1:0] issue_mult_fu_start;
    logic [NUM_MULT_UNITS-1:0] issue_mult_fu_busy; 

    // I/O ALU/CMP Units <-> CDB Arbiter
    logic [NUM_ALU_CMP_UNITS-1:0] alu_cmp_cdb_ack;
    logic [NUM_ALU_CMP_UNITS-1:0] alu_cmp_fu_done;
    fu_cdb_data_t alu_cmp_cdb_data[NUM_ALU_CMP_UNITS];

    // I/O Mult Units <-> CDB Arbiter
    logic [NUM_MULT_UNITS-1:0] mult_cdb_ack;
    logic [NUM_MULT_UNITS-1:0] mult_fu_done;
    fu_cdb_data_t mult_cdb_data[NUM_MULT_UNITS];

    // Branch/mispredicts
    
    logic mispredict;
    logic [NUM_ROB_ENTRIES_BITS-1:0] rob_number_br_queue;
    logic br_queue_mask[SS];
    logic [NUM_PHYS_REGS_BITS - 1:0] rrf_mispredict_table[32];

    // I/O Branch Predictor <-> IF stage
    // use imem_addr that is given to i_cache
    logic [INSTR_FETCH_NUM - 1 : 0] br_taken;

    // I/O Rename Dispatch <-> Load RS stations
    logic [SS_FACTOR_BITS : 0] load_rs_push_limit;
    load_rs_entry_t load_entry [SS_FACTOR];
    logic [SS_FACTOR_BITS : 0] load_push;

    // I/O Load RS stations <-> store queue
    rob_num_t store_dependency;
    logic exists_store_dependency;

    // I/O Load RS stations <-> mem arbiter
    load_rs_entry_t load_rs_output [NUM_LOAD_RS];
    logic load_rs_free;
    logic [LOAD_RS_BITS - 1 : 0] load_rs_free_idx;

    //RVFI

    rvfi_data_t rvfi_data_rob[SS];

    // instruction cache
    logic   [31:0]  i_ufp_addr;
    logic   [31:0]  i_ufp_addr_curr;
    logic   [3:0]   i_ufp_rmask;
    logic   [INSTR_FETCH_NUM * 32 - 1 : 0]  i_ufp_rdata;
    logic           i_ufp_resp;

    logic   [31:0]  i_dfp_addr;
    logic           i_dfp_read;
    logic           i_dfp_write;
    logic   [255:0] i_dfp_rdata;
    logic   [255:0] i_dfp_wdata;
    logic           i_dfp_resp;

    // data cache
    logic   [31:0]  d_ufp_addr;
    logic   [3:0]   d_ufp_rmask;
    logic   [3:0]   d_ufp_wmask;
    logic   [31:0]  d_ufp_rdata;
    logic   [31:0]  d_ufp_wdata;
    logic           d_ufp_resp;

    logic   [31:0]  d_dfp_addr;
    logic           d_dfp_read;
    logic           d_dfp_write;
    logic   [255:0] d_dfp_rdata;
    logic   [255:0] d_dfp_wdata;
    logic           d_dfp_resp;

    if_stage_new if_stage(
      .clk(clk),
      .rst(rst),
      .mispredict(mispredict),
      .imem_addr(i_ufp_addr),
      .imem_addr_curr(i_ufp_addr_curr),
      .imem_rmask(i_ufp_rmask),
      .imem_resp(i_ufp_resp),
      .imem_rdata(i_ufp_rdata),
      .instr_queue_input(instr_queue_input),
      .instr_queue_full(instr_queue_full),
      .instr_queue_push(instr_queue_push),
      .br_PC(br_PC),
      .br_taken(br_taken)
    );

    queue #(.WIDTH(INSTR_FETCH_NUM * $bits(pc_instr_t)), .DEPTH(8)) instr_queue(
      .clk(clk),
      .rst(rst),
      .mispredict(mispredict),
      .real_input_ligma(instr_queue_input),
      .real_output_ligma(instr_queue_output),
      .push(instr_queue_push),
      // .push(cp1_instr_queue_push), // remove later, this is for testing cp1
      .pop(instr_queue_pop),
      .full(instr_queue_full),
      .empty(instr_queue_empty)
    );

    rename_dispatch rename_dispatch_stage(
      .clk(clk),
      .rst(rst),
      .instr_bundle(instr_queue_output),
      .instr_queue_empty(instr_queue_empty),
      .instr_queue_pop(instr_queue_pop),

      .res_stations_mask_in(dispatch_rs_busy),
      .res_stations_mask_out(dispatch_rs_we),
      .res_station_entry(dispatch_rs_data),

      // ROB I/O
      .rob_number_dispatch(rob_number_dispatch),
      .num_free_robs(num_free_regs_rob),
      .rob_push(rob_push),
      .rob_entry(rob_entries_to_rob),
      .mispredict(mispredict),

      // Rat I/O
      .ps1(ps1_to_dispatch),
      .ps2(ps2_to_dispatch),
    //   .regf_we_rat(rat_update),
      .rd_dispatch(rd_to_rat),
      .pd_dispatch(pd_to_rat),
      .rs1(rs1_to_rat),
      .rs2(rs2_to_rat),
      
      // Free list I/O
      .num_free_regs(num_free_regs_free_list),
      .free_reg(used_registers_to_dispatch),
      .free_list_pop(free_list_pop),

      // regfile I/O
      .reg_invalidate_idx(invalidate_registers),
      .reg_invalidate_mask(invalidate_register_mask),

      // branch_queue I/O
      .num_free_brq_entries(num_free_brq_entries),
      .brq_entry(brq_entry),
      .brq_push(brq_push),

      // SQ I/O
      .store_queue_free(lsq_free),
      .sq_entry(dispatch_store_load_input),
      .sq_push(lsq_dispatch_push),

      // load RS I/O
      .load_rs_push_limit(load_rs_push_limit),
      .load_entry(load_entry),
      .load_push(load_push)

    );

    rat rat(
      .clk(clk),
      .rst(rst),
      .mispredict(mispredict),      
    //   .rat_update(rat_update),
      .rd_dispatch(rd_to_rat),
      .pd_dispatch(pd_to_rat),
      .rrf_mispredict_table(rrf_mispredict_table),
      .rs1(rs1_to_rat),
      .rs2(rs2_to_rat),
      .ps1(ps1_to_dispatch),
      .ps2(ps2_to_dispatch)
    );

    rrf rrf(
      .clk(clk),
      .rst(rst),
      .commit_cnt(rrf_commit_cnt),
      .rd_rob(arch_reg_to_rrf),
      .pd_rob(phys_reg_to_rrf),
      .free_list_push(free_list_push),
      .old_phys_reg(old_phys_regs_to_free_list),
      .rrf_mispredict_table(rrf_mispredict_table)
    );

    free_list free_list(
      .clk(clk),
      .rst(rst),
      .mispredict(mispredict),
      .freed_register(old_phys_regs_to_free_list),
      .used_register(used_registers_to_dispatch),
      .rrf_push(free_list_push),
      .dispatch_pop(free_list_pop),
      .num_free_regs(num_free_regs_free_list)
    );

    rob rob(
      .clk(clk),
      .rst(rst),
      .cdb_entries(cdb),
      .dispatch_push(rob_push),
      .dispatch_input(rob_entries_to_rob),
      .commit_cnt(rrf_commit_cnt),
      .rrf_arch_reg(arch_reg_to_rrf),
      .rrf_phys_reg(phys_reg_to_rrf),
      .num_free_regs(num_free_regs_rob),
      .rvfi_rob_output(rvfi_data_rob),
      .rob_number_head(rob_number_br_queue),
      .rob_number_tail(rob_number_dispatch),
      .br_queue_mask(br_queue_mask),
      .mispredict(mispredict)
    );

    branch_queue branch_queue(
      .clk(clk), 
      .rst(rst),
      .mispredict(mispredict),
      .brq_entry(brq_entry),
      .cdb_entries(cdb),
      .brq_push(brq_push),
      .commit_cnt(rrf_commit_cnt),
      .rob_number_br_queue(rob_number_br_queue),
      .br_queue_mask(br_queue_mask),
      .br_PC(br_PC),
      .num_free_brq_entries(num_free_brq_entries)
    );

    store_queue sq(
        .clk(clk),
        .rst(rst),
        .mispredict(mispredict),
        .dispatch_push(lsq_dispatch_push),
        .arbiter_pop(lsq_arbiter_pop),
        .dispatch_store_load_input(dispatch_store_load_input),
        .arbiter_store_load_output(arbiter_store_load_output),
        .lsq_free(lsq_free),
        .lsq_empty(lsq_empty),

        .exists_store_dependency(exists_store_dependency),
        .store_dependency(store_dependency)
    );

    load_rs load_rs_i(
      .clk(clk),
      .rst(rst),

      .input_entries(load_entry),
      .num_push(load_push),
      .push_limit(load_rs_push_limit),

      .valid_reg(reg_file_valid),
      .store_load_cdb(cdb_mem),
      .store_dependency(store_dependency),
      .exists_store_dependency(exists_store_dependency),
      .mispredict(mispredict),

      .free(load_rs_free),
      .free_idx(load_rs_free_idx),
      .output_entries(load_rs_output)
    );

    reservation_station rs_i(
      .clk(clk),
      .rst(rst),
      .rs_we(dispatch_rs_we),
      .rs_wdata(dispatch_rs_data),
      .rs_to_free(rs_issue_to_free),
      .busy_rs(dispatch_rs_busy),
      .rs_curr(rs_issue_rs_curr),
      .branch_mispredict(mispredict)
    );

    register_file rf_i(
      .clk(clk),
      .rst(rst),
      .cdb(cdb),
      .ps1_s(reg_file_ps1_s),
      .ps2_s(reg_file_ps2_s),
      .invalid_reg(invalidate_registers),
      .invalid_mask(invalidate_register_mask),
      
      .ps1_v(reg_file_ps1_v),
      .ps2_v(reg_file_ps2_v),
      .valid_reg(reg_file_valid)
    );

    issue_arb_wrapper issue_i(
      .rs_curr(rs_issue_rs_curr),
      .ps1_v(issue_reg_file_ps1_v),
      .ps2_v(issue_reg_file_ps2_v),
      .valid_reg(reg_file_valid),
      .alu_cmp_busy(issue_alu_cmp_fu_busy),
      .mult_busy(issue_mult_fu_busy),

      .rs_to_free(rs_issue_to_free),
      .ps1_s(issue_reg_file_ps1_s),
      .ps2_s(issue_reg_file_ps2_s),
      .alu_cmp_input_data(issue_alu_cmp_input_data),
      .alu_cmp_start(issue_alu_cmp_fu_start),
      .mult_input_data(issue_mult_input_data),
      .mult_start(issue_mult_fu_start)
    );

    alu_cmp_units alu_cmp_units_i(
      .clk(clk),
      .rst(rst),
      .input_data(issue_alu_cmp_input_data),
      .fu_start(issue_alu_cmp_fu_start),
      .cdb_ack(alu_cmp_cdb_ack),

      .output_data(alu_cmp_cdb_data),
      .fu_busy(issue_alu_cmp_fu_busy),
      .fu_done(alu_cmp_fu_done),
      .branch_mispredict(mispredict)
    );

    mult_units mult_units_i(
      .clk(clk),
      .rst(rst),
      .input_data(issue_mult_input_data),
      .fu_start(issue_mult_fu_start),
      .cdb_ack(mult_cdb_ack),

      .output_data(mult_cdb_data),
      .fu_busy(issue_mult_fu_busy),
      .fu_done(mult_fu_done),
      .branch_mispredict(mispredict)
    );

    cdb_arb_wrapper cdb_arbiter_i(
      .alu_cmp_done(alu_cmp_fu_done),
      .alu_cmp_output_data(alu_cmp_cdb_data),
      .mult_done(mult_fu_done),
      .mult_output_data(mult_cdb_data),

      .cdb(cdb_alu_mul),
      .alu_cmp_ack(alu_cmp_cdb_ack),
      .mult_ack(mult_cdb_ack)
    );

    mem_arbiter_new mem_arbiter(
        .clk(clk),
        .rst(rst),
        .mispredict(mispredict),

        .sq_head(arbiter_store_load_output),
        .sq_empty(lsq_empty),
        .pop(lsq_arbiter_pop),

        .ps1_v(mem_issue_reg_file_ps1_v),
        .ps2_v(mem_issue_reg_file_ps2_v),
        .valid_reg(reg_file_valid), // valid_registers in reg file
        .ps1_s(mem_issue_reg_file_ps1_s),
        .ps2_s(mem_issue_reg_file_ps2_s),

        .rob_head(rob_number_br_queue), 
        .cdb(cdb_mem),
        .d_cache_rdata(d_ufp_rdata),
        .d_cache_resp(d_ufp_resp),
        .d_cache_addr(d_ufp_addr),
        .d_cache_rmask(d_ufp_rmask),
        .d_cache_wmask(d_ufp_wmask),
        .d_cache_wdata(d_ufp_wdata),

        .load_rs(load_rs_output),
        .free(load_rs_free),
        .free_idx(load_rs_free_idx)
    );

    cache d_cache(
      .clk(clk),
      .rst(rst),
      
      .ufp_addr(d_ufp_addr),
      .ufp_rmask(d_ufp_rmask),
      .ufp_wmask(d_ufp_wmask),
      .ufp_rdata(d_ufp_rdata),
      .ufp_wdata(d_ufp_wdata),
      .ufp_resp(d_ufp_resp),

      .dfp_addr(d_dfp_addr),
      .dfp_read(d_dfp_read),
      .dfp_write(d_dfp_write),
      .dfp_rdata(d_dfp_rdata),
      .dfp_wdata(d_dfp_wdata),
      .dfp_resp(d_dfp_resp)
    );
    
    cheese_cache #(.OUTPUT_BYTES(4 * INSTR_FETCH_NUM)) i_cache(
      .clk(clk),
      .rst(rst),
      
      .ufp_addr(i_ufp_addr),
      .ufp_rmask(i_ufp_rmask),
      .ufp_rdata(i_ufp_rdata),
      .ufp_resp(i_ufp_resp),

      .dfp_addr(i_dfp_addr),
      .dfp_read(i_dfp_read),
      .dfp_write(i_dfp_write),
      .dfp_rdata(i_dfp_rdata),
      .dfp_wdata(i_dfp_wdata),
      .dfp_resp(i_dfp_resp)
    );

    cacheline_adaptor cacheline_adaptor_i
    (
        .clk(clk),
        .rst(rst),

        .i_addr(i_dfp_addr),
        .i_read(i_dfp_read),
        .i_rdata(i_dfp_rdata),
        .i_resp(i_dfp_resp),
 
        // d-cache <-> adaptor sign als
        .d_addr(d_dfp_addr),
        .d_read(d_dfp_read),
        .d_write(d_dfp_write),
        .d_rdata(d_dfp_rdata),
        .d_wdata(d_dfp_wdata),
        .d_resp(d_dfp_resp),
 
        // adaptor <-> mem signals 
        .mem_addr(bmem_addr),
        .mem_read(bmem_read),
        .mem_write(bmem_write),
        .mem_wdata(bmem_wdata),
        .mem_ready(bmem_ready),
 
        .mem_raddr(bmem_raddr),
        .mem_rdata(bmem_rdata),
        .mem_rvalid(bmem_rvalid)
    );

    br_pred br_pred
    (
      .clk(clk),
      .rst(rst),
      .imem_addr(i_ufp_addr_curr),
      .cdb(cdb),

      .br_taken(br_taken)
    );

    logic [63:0] dummy_order;
    logic [31:0] dummy_31;
    logic dummy_commit;
    logic [4:0] dummy_rs;
    logic [3:0] dummy_mask;

    always_comb begin
        dummy_order = '0;
        dummy_31 = '0;
        dummy_commit = '0;
        dummy_rs = '0;
        dummy_mask = '0;
    end

endmodule : cpu



















































/*
                                                                                                    
                                          =.             #-                                         
                                          *-            **=                                         
                                         +#*:           **+:                                        
                                         *#*+:         +***-                                        
                                         ****-         ***#=                                        
                                        +#*##*:       +****+                                        
                                        *#***#+:      ****+*-                                       
                                        *#**+*#-      ***++*+                                       
                                        *#*+=+#+     +#*#+=**-                                      
                                       =#**+==+#-   =****==**=                                      
                                       =#**+==+#+.  +**#*==**=                                      
                                       =#**+===**-  +**#+==**=                                      
                                       =#**+===**=  +***+==**+                                      
                                       =#**+===*#=  ****+=+**=                                      
                                        *#**===*#= =****+++#*                                       
                                        +#**==+*#= =****+++*+                                       
                                        +###+=+*#= =****++**                                        
                                        =*##*++**=  +#**+*#*                                        
                                         +###++#*-  +#*#*#*                                         
                                          *##**#+   +*####+                                         
                                          +###*#=    +###*                                          
                                           +####= *###*+#*                                          
                                            *###****####*+.                                         
                                             #%%##@#******%*:                                       
                                            +#%##%***********=                                      
                                            *#####******++**##-                                     
                                           +#%##***#*#******#*+                                     
                                           *#%###**#*+*#*****=*+                                    
                                           *%%######*#=:#**##*--                                    
                                          ##%%##*++*+--:****=-=:--#@                                
                                          *##+=-::::-=++-:+==-==+++*@                               
                                          **+=--=+++++*#*=:=-----=++  @@@                           
                                          ##+=----=++%@@@+=--:-=+*=                                 
                                          ###+=--::---#%%#+-=-----=-                                
                                         *#%#+=--:::::=#**+=-::::---                                
                                       *#%%%#++=--::::-----::::::-=-                                
                                     *######*++==---::::::::::::-===                                
                                  **####***#==+==-----------::--=++*-                               
                                **##*******+---=-------::::::--====*#=:                             
                              *###*********=-------:::::::::::-----=#**=                            
                           +*###*******###*--:::::::::::::::::::::--=#***-                          
                         =*###*****######*--:::::::::::........::::-==##*#*-                        
                        +###***####%%%%#+--::::::::::...........:::--=+##**#*-                      
                      +*###**###%%%%%##=---:::::::::CHIG🅱UNG😮😮😮:--=*%#***#=                     
                     +*###*###%%%%%##+------::::::::::...........::::-==#%#***#+                    
                    +*######%%%%%##*=-------::::::::::...........::::--=+%%#**##*                   
                    +##+==*#%%%%##+=---------:::::::::...........::::--==#%%#++*#*                  
                   ==-==----*%%##+=----------:::::::::..........::::::--=+#==----:.                 
                   =+=-:-...=#%#+==-----------::::::::::.......:::::::--=++=:.::--==                
                   =+=-.::.::.:--==-----------::::::::::::..:::::::::-=:...:.::.-:-:                
                   =+-=:::.-==--====----------:::::::::::::::::::::::-=++*+-....::--                
                   ==--:::::-##*+===-----------:::::::::::::::::::::---=++=:.:..::=                 
                   -==-::::::=+======------------::::::::::::::::::----==+-:--:-===                 
                    ===-::--::=+=======-------------:::::::::::::-----=====++-===+                  
                     -===--==::=+=======-----------------::----------===+*+=++++                    
                      +****=+*++++========--------------------------===+++=                         
                      +*#%%%%#++++++==========-------------------=====++++                          
                      +*##%%%%*+++++++===============------==========+++++                          
                      =+*#%%%%#**++++++++==========================++++*+                           
                       ++##%%%%****++++++++++==================+++++++*+                            
                        +*#%%%%%*****+++++++++++++++++++++++++++++++***                             
                         +*#%%%%%********+++++++++++++++++++++++******+=--                          
                          ++*#%%%%#*************+++++++************#*-:::--:                        
                            +**#%%%%#***************************#*+=:::-+-==                        
                   --====+*##%%**##%%%%#***********************++==-::-++***                        
                -==----:::=***##%%%#%%%%%%%%##*+**************+++++++***                            
               :---:::::::::-+***##%%%%#****                                                        
              :-=--==-:...:::::--==++++**                                                           
              -=++++--::::---===++++*                                                               
               +****=++===+++++                                                                     
                     *****   
*/
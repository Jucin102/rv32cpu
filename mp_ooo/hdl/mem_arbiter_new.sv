module mem_arbiter_new
import rv32i_types::*;
(   
    input clk, rst, mispredict,

    // store queue I/O
    input lsq_entry_t sq_head,
    input logic sq_empty,
    output logic pop,

    // load rs I/O
    input load_rs_entry_t load_rs[NUM_LOAD_RS],
    output logic free,
    output logic [LOAD_RS_BITS - 1 : 0] free_idx,

    // reg file I/O
    input logic [31:0] ps1_v, ps2_v,
    input logic [NUM_PHYS_REGS - 1 : 0] valid_reg,
    output phys_reg ps1_s, ps2_s,

    // ROB I/O
    input logic [NUM_ROB_ENTRIES_BITS - 1 : 0] rob_head,

    // CDB I/O
    output cdb_t cdb,

    // D cache I/O
    input logic [31:0] d_cache_rdata,
    input logic d_cache_resp,
    output logic [31:0] d_cache_addr,
    output logic [3:0] d_cache_rmask,
    output logic [3:0] d_cache_wmask, 
    output logic [31:0] d_cache_wdata
);
    // state
    enum logic [1:0] {MEM_IDLE, MEM_BUSY, MEM_INVALID} state, state_next;

    // pd_v
    logic [31:0] pd_v;

    logic [31:0] ps2_v_reg, ps1_v_reg;

    // decoding instr to execute
    lsq_entry_t instr_to_execute, instr_to_execute_reg;
    logic valid_instr_to_execute;
    logic load_ready;
    logic [LOAD_RS_BITS - 1 : 0] ready_load_idx, ready_load_idx_reg;
    logic store_ready;
    logic ready_to_issue;

    logic [31:0] addr_reg;

    // for decoding instr
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [6:0] opcode;
    logic [31:0] i_imm, s_imm, b_imm, u_imm, j_imm;
    logic [31:0] temp_addr;
    logic [31:0] instr;

    logic [LOAD_RS_BITS - 1 : 0] next_start_idx;

    always_ff @(posedge clk) // setting the next_start_idx
    begin
        if (rst | mispredict)
        begin
            next_start_idx <= '0;
        end
        else
        begin
            if (state_next == MEM_BUSY && state == MEM_IDLE && store_ready == 1'b0 && load_ready == 1'b1) // issue a load
            begin
                next_start_idx <= (LOAD_RS_BITS)'(ready_load_idx + (LOAD_RS_BITS)'(1));
            end
        end
    end

    always_comb // checking for ready loads
    begin
        load_ready = 1'b0;
        ready_load_idx = 'x;

        for (int unsigned i = 0; i < NUM_LOAD_RS; ++i)
        begin
            if (load_rs[(LOAD_RS_BITS)'(next_start_idx + (LOAD_RS_BITS)'(i))].state == READY) // && load_rs[(LOAD_RS_BITS)'(i)].rob_num == rob_head) // test if execute at commit works
            begin
                load_ready = 1'b1;
                ready_load_idx = (LOAD_RS_BITS)'(next_start_idx + (LOAD_RS_BITS)'(i));
                break;
            end
        end
    end

    always_comb // checking for ready stores
    begin
        store_ready = (!(sq_empty == 1'b1)) && (rob_head == sq_head.rob_num) && (valid_reg[sq_head.ps1_s] == 1'b1) && (valid_reg[sq_head.ps2_s] == 1'b1);
    end

    always_comb // assigning instr_to_execute
    begin
        if (store_ready)
        begin
            instr_to_execute = sq_head;
        end
        else if (load_ready)
        begin
            instr_to_execute.ps1_s = load_rs[ready_load_idx].ps1_s;
            instr_to_execute.ps2_s = 'x;
            instr_to_execute.pd_s = load_rs[ready_load_idx].pd_s;
            instr_to_execute.rob_num = load_rs[ready_load_idx].rob_num;
            instr_to_execute.store_load_inst = load_rs[ready_load_idx].instr;
            instr_to_execute.rvfi_data = load_rs[ready_load_idx].rvfi_data;
        end
        else
        begin
            instr_to_execute = 'x;
        end
    end

    always_ff @(posedge clk)
    begin
        if (rst)
        begin
            instr_to_execute_reg <= 'x;
            valid_instr_to_execute <= '0;
            ready_load_idx_reg <= 'x;
            addr_reg <= 'x;
            ps1_v_reg <= 'x;
            ps2_v_reg <= 'x;
        end
        else
        begin
            unique case (state)
                MEM_IDLE:
                begin
                    if (ready_to_issue == 1'b1 && mispredict == 1'b0)
                    begin
                        instr_to_execute_reg <= instr_to_execute;
                        valid_instr_to_execute <= '1;
                        ready_load_idx_reg <= ready_load_idx;
                        addr_reg <= temp_addr;
                        ps1_v_reg <= ps1_v;
                        ps2_v_reg <= ps2_v;
                    end
                end
                MEM_BUSY:
                begin
                    if (d_cache_resp == 1'b1)
                    begin
                        instr_to_execute_reg <= 'x;
                        valid_instr_to_execute <= '0;
                        ready_load_idx_reg <= 'x;
                        addr_reg <= 'x;
                        ps1_v_reg <= 'x;
                        ps2_v_reg <= 'x;
                    end
                end
                MEM_INVALID:
                begin
                    if (d_cache_resp == 1'b1)
                    begin
                        instr_to_execute_reg <= 'x;
                        valid_instr_to_execute <= '0;
                        ready_load_idx_reg <= 'x;
                        addr_reg <= 'x;
                        ps1_v_reg <= 'x;
                        ps2_v_reg <= 'x;
                    end
                end
                default: ; 
            endcase
        end
    end

    always_comb // decodes instruction to execute
    begin
        instr = instr_to_execute_reg.store_load_inst.word;
        funct3 = instr[14:12];
        funct7 = instr[31:25];
        opcode = instr[6:0];
    end

    always_comb
    begin
        i_imm  = {{21{instr_to_execute.store_load_inst.word[31]}}, instr_to_execute.store_load_inst.word[30:20]};
        s_imm  = {{21{instr_to_execute.store_load_inst.word[31]}}, instr_to_execute.store_load_inst.word[30:25], instr_to_execute.store_load_inst.word[11:7]};
    end

    assign ready_to_issue = store_ready | load_ready;

    // state transition
    always_comb
    begin
        if (rst)
        begin
            state_next = MEM_IDLE;
        end
        else
        begin
            unique case (state)
                MEM_IDLE:
                begin
                    if (ready_to_issue == 1'b1 && mispredict == 1'b0)
                    begin
                        state_next = MEM_BUSY;
                    end
                    else
                    begin
                        state_next = MEM_IDLE;
                    end
                end
                MEM_BUSY:
                begin
                    if (d_cache_resp == 1'b1)
                    begin
                        state_next = MEM_IDLE;
                    end
                    else if (mispredict == 1'b1 && d_cache_resp == 1'b0)
                    begin
                        state_next = MEM_INVALID;
                    end
                    else
                    begin
                        state_next = MEM_BUSY;
                    end
                end
                MEM_INVALID:
                begin
                    if (d_cache_resp == 1'b1)
                    begin
                        state_next = MEM_IDLE;
                    end
                    else
                    begin
                        state_next = MEM_INVALID;
                    end
                end
                default:
                begin
                    state_next = state;
                end
            endcase
        end
    end

    always_ff @(posedge clk)
    begin
        state <= state_next;
    end

    // outputs 
    // assigning temp_addr
    always_comb
    begin
        if (store_ready == 1'b1)
        begin
            temp_addr = ps1_v + s_imm;
        end
        else
        begin
            temp_addr = ps1_v + i_imm;
        end
    end

    always_comb // memory interface
    begin
        if ((state inside {MEM_BUSY, MEM_INVALID}) && valid_instr_to_execute == 1'b1) // if next state (we cheat a little here) or current state is state where cache is busy (cheating is not working, only start sending signals when we reach MEM_BUSY or MEM_INVALID)
        begin
            d_cache_addr = 'x;
            d_cache_rmask = '0;
            d_cache_wmask = '0;
            d_cache_wdata = 'x;
            unique case (opcode)
                op_load:
                begin
                    d_cache_addr = (addr_reg & 32'hfffffffc);
                    unique case (funct3)
                        lb, lbu: d_cache_rmask = 4'b0001 << addr_reg[1:0];
                        lh, lhu: d_cache_rmask = 4'b0011 << addr_reg[1:0];
                        lw:      d_cache_rmask = 4'b1111;
                        default: d_cache_rmask = '0;
                    endcase
                end
                op_store:
                begin
                    d_cache_addr = (addr_reg & 32'hfffffffc);
                    unique case (funct3)
                        sb: d_cache_wmask = 4'b0001 << addr_reg[1:0];
                        sh: d_cache_wmask = 4'b0011 << addr_reg[1:0];
                        sw: d_cache_wmask = 4'b1111;
                        default: d_cache_wmask = '0;
                    endcase
                    unique case (funct3)
                        sb: d_cache_wdata[8 *addr_reg[1:0] +: 8 ] = ps2_v_reg[7 :0];
                        sh: d_cache_wdata[16*addr_reg[1]   +: 16] = ps2_v_reg[15:0];
                        sw: d_cache_wdata = ps2_v_reg;
                        default: d_cache_wdata = 'x;
                    endcase
                end
                default:
                begin
                    d_cache_addr = 'x;
                    d_cache_rmask = '0;
                    d_cache_wmask = '0;
                    d_cache_wdata = 'x;
                end
            endcase
        end
        else
        begin
            d_cache_addr = 'x;
            d_cache_rmask = '0;
            d_cache_wmask = '0;
            d_cache_wdata = 'x;
        end
    end

    always_comb // setting pd_v
    begin
        if (opcode == op_load)
        begin
            unique case (funct3) // temp_addr will 
                lb : pd_v = {{24{d_cache_rdata[7 +8 *addr_reg[1:0]]}}, d_cache_rdata[8 *addr_reg[1:0] +: 8 ]};
                lbu: pd_v = {{24{1'b0}}                          , d_cache_rdata[8 *addr_reg[1:0] +: 8 ]};
                lh : pd_v = {{16{d_cache_rdata[15+16*addr_reg[1]  ]}}, d_cache_rdata[16*addr_reg[1]   +: 16]};
                lhu: pd_v = {{16{1'b0}}                          , d_cache_rdata[16*addr_reg[1]   +: 16]};
                lw : pd_v = d_cache_rdata;
                default: pd_v = 'x;
            endcase
        end
        else
        begin
            pd_v = 'x;
        end
    end

    always_comb // outputs to load rs and store queue
    begin
        // defaults
        free = 1'b0;
        free_idx = 'x;

        pop = 1'b0;

        if (state == MEM_BUSY && d_cache_resp == 1'b1)
        begin
            if (opcode == op_load)
            begin
                free = 1'b1;
                free_idx = ready_load_idx_reg;
            end
            else
            begin
                pop = 1'b1;
            end
        end
    end

    always_comb // register outputs
    begin
        ps1_s = instr_to_execute.ps1_s;
        ps2_s = instr_to_execute.ps2_s;
    end

    always_comb // register and cdb outputs
    begin
        if ((state == MEM_BUSY) && (d_cache_resp == 1'b1) && (mispredict == 1'b0)) // might need to explicitly say no mispredict
        begin
            cdb.valid = 1'b1;
            if (opcode == op_load)
            begin
                cdb.pd_s = instr_to_execute_reg.pd_s; // for stores, this is always physical 0
            end
            else
            begin
                cdb.pd_s = '0;
            end
            cdb.rob_num = instr_to_execute_reg.rob_num;
            cdb.pd_v = pd_v;

            cdb.rvfi_data = instr_to_execute_reg.rvfi_data;
            cdb.rvfi_data.rs1_v = ps1_v_reg;
            cdb.rvfi_data.rs2_v = ps2_v_reg;
            cdb.rvfi_data.rd_wdata = pd_v;
            cdb.rvfi_data.mem_addr = d_cache_addr;
            cdb.rvfi_data.mem_rmask = d_cache_rmask;
            cdb.rvfi_data.mem_wmask = d_cache_wmask;
            cdb.rvfi_data.mem_rdata = d_cache_rdata;
            cdb.rvfi_data.mem_wdata = d_cache_wdata;

            cdb.br_en = 1'b0;
            cdb.branch_pc = 'x;

            cdb.instr_pc = 'x;
            cdb.instr_is_br = 1'b0;
            cdb.br_taken = 1'b0;
        end
        else
        begin
            cdb = 'x;
            cdb.valid = 1'b0;
        end
    end
endmodule
module mem_arbiter
import rv32i_types::*;
(   
    input clk, rst, mispredict,

    // LSQ I/O
    input lsq_entry_t lsq_head,
    input logic lsq_empty,
    output logic pop,

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
    logic busy, next_busy, ready_to_issue, store_ready, load_ready;
    logic [31:0] pd_v;
    
    // decoding instr
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [6:0] opcode;
    logic [31:0] i_imm, s_imm, b_imm, u_imm, j_imm;
    logic [31:0] temp_addr;
    logic [31:0] instr;

    always_comb
    begin
        instr = lsq_head.store_load_inst.word;
        funct3 = instr[14:12];
        funct7 = instr[31:25];
        opcode = instr[6:0];
        i_imm  = {{21{instr[31]}}, instr[30:20]};
        s_imm  = {{21{instr[31]}}, instr[30:25], instr[11:7]};
        b_imm  = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
        u_imm  = {instr[31:12], 12'h000};
        j_imm  = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
    end

    // setting state
    always_comb
    begin
        store_ready = (opcode == op_store) && (valid_reg[lsq_head.ps1_s] == 1'b1) && (valid_reg[lsq_head.ps2_s] == 1'b1);
        load_ready = (opcode == op_load) && (valid_reg[lsq_head.ps1_s] == 1'b1);
        ready_to_issue = (!(lsq_empty == 1'b1) && (rob_head == lsq_head.rob_num) && (store_ready == 1'b1 || load_ready == 1'b1));

        unique case (busy)
            1'b0:
            begin
                if (ready_to_issue)
                begin
                    next_busy = 1'b1;
                end
                else
                begin
                    next_busy = 1'b0;
                end
            end
            1'b1:
            begin
                if (d_cache_resp)
                begin
                    next_busy = 1'b0;
                end
                else
                begin
                    next_busy = 1'b1;
                end
            end
            default: ;
        endcase
    end

    always_ff @(posedge clk)
    begin
        if ((rst == 1'b1) || (mispredict == 1'b1))
        begin
            busy <= 1'b0;
        end
        else
        begin
            busy <= next_busy;
        end
    end

    // outputs
    // assigning temp_addr
    always_comb
    begin
        if (opcode == op_load)
        begin
            temp_addr = i_imm + ps1_v;
        end
        else
        begin
            temp_addr = ps1_v + s_imm;
        end
    end

    always_comb // memory interface
    begin
        if (((busy == 1'b0) && (ready_to_issue == 1'b1)) || (busy == 1'b1))
        begin
            d_cache_addr = 'x;
            d_cache_rmask = '0;
            d_cache_wmask = '0;
            d_cache_wdata = 'x;
            unique case (opcode)
                op_load:
                begin
                    d_cache_addr = (temp_addr & 32'hfffffffc);
                    unique case (funct3)
                        lb, lbu: d_cache_rmask = 4'b0001 << temp_addr[1:0];
                        lh, lhu: d_cache_rmask = 4'b0011 << temp_addr[1:0];
                        lw:      d_cache_rmask = 4'b1111;
                        default: d_cache_rmask = '0;
                    endcase
                end
                op_store:
                begin
                    d_cache_addr = (temp_addr & 32'hfffffffc);
                    unique case (funct3)
                        sb: d_cache_wmask = 4'b0001 << temp_addr[1:0];
                        sh: d_cache_wmask = 4'b0011 << temp_addr[1:0];
                        sw: d_cache_wmask = 4'b1111;
                        default: d_cache_wmask = '0;
                    endcase
                    unique case (funct3)
                        sb: d_cache_wdata[8 *temp_addr[1:0] +: 8 ] = ps2_v[7 :0];
                        sh: d_cache_wdata[16*temp_addr[1]   +: 16] = ps2_v[15:0];
                        sw: d_cache_wdata = ps2_v;
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
                lb : pd_v = {{24{d_cache_rdata[7 +8 *temp_addr[1:0]]}}, d_cache_rdata[8 *temp_addr[1:0] +: 8 ]};
                lbu: pd_v = {{24{1'b0}}                          , d_cache_rdata[8 *temp_addr[1:0] +: 8 ]};
                lh : pd_v = {{16{d_cache_rdata[15+16*temp_addr[1]  ]}}, d_cache_rdata[16*temp_addr[1]   +: 16]};
                lhu: pd_v = {{16{1'b0}}                          , d_cache_rdata[16*temp_addr[1]   +: 16]};
                lw : pd_v = d_cache_rdata;
                default: pd_v = 'x;
            endcase
        end
        else
        begin
            pd_v = 'x;
        end
    end

    always_comb // excluding memory interface
    begin
        if ((busy == 1'b1) && (d_cache_resp == 1'b1))
        begin
            pop = 1'b1;
        end
        else
        begin
            pop = 1'b0;
        end

        ps1_s = lsq_head.ps1_s;
        ps2_s = lsq_head.ps2_s;

        if ((busy == 1'b1) && (d_cache_resp == 1'b1))
        begin
            cdb.valid = 1'b1;
            cdb.pd_s = lsq_head.pd_s; // for stores, this is always physical 0
            cdb.rob_num = lsq_head.rob_num;
            cdb.pd_v = pd_v;

            cdb.rvfi_data = lsq_head.rvfi_data;
            cdb.rvfi_data.rs1_v = ps1_v;
            cdb.rvfi_data.rs2_v = ps2_v;
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
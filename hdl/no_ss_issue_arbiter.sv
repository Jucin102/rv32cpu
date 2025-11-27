module no_ss_issue_arbiter // assumes that NUM_ISSUE is 2
import rv32i_types::*;
(
    // no clk or rst because purely combinational
    input rs_entry_t rs_curr [NUM_RES_STATIONS],
    input logic [31:0] ps1_v [NUM_ALU_MULT_ISSUE],
    input logic [31:0] ps2_v [NUM_ALU_MULT_ISSUE],
    input logic [NUM_PHYS_REGS-1:0] valid_reg,
    input logic [NUM_ALU_CMP_UNITS-1:0] alu_cmp_busy,
    input logic [NUM_MULT_UNITS-1:0] mult_busy,
    
    output logic [NUM_RES_STATIONS-1:0] rs_to_free,
    output phys_reg ps1_s [NUM_ALU_MULT_ISSUE],
    output phys_reg ps2_s [NUM_ALU_MULT_ISSUE],
    output issue_fu_data_t alu_cmp_input_data[NUM_ALU_CMP_UNITS],
    output logic [NUM_ALU_CMP_UNITS-1:0] alu_cmp_start,
    output issue_fu_data_t mult_input_data[NUM_MULT_UNITS],
    output logic [NUM_MULT_UNITS-1:0] mult_start
);
    // dedicate register port 0 to alu/cmp instr and port 1 to mult instr
    rs_entry_t ready_alu_cmp_rs, ready_mult_rs;
    logic [RES_STATION_BITS - 1 : 0] ready_alu_cmp_rs_idx, ready_mult_rs_idx;
    logic exists_ready_alu_cmp_rs, exists_ready_mult_rs;
    logic [$clog2(NUM_ALU_CMP_UNITS)-1:0] free_alu_cmp_fu_idx;
    logic [$clog2(NUM_MULT_UNITS)-1:0] free_mult_fu_idx;
    logic exists_free_alu_cmp_fu, exists_free_mult_fu;

    // search for ready rs
    always_comb
    begin
        // default values
        exists_ready_alu_cmp_rs = 1'b0;
        ready_alu_cmp_rs = 'x;
        exists_ready_mult_rs = 1'b0;
        ready_mult_rs = 'x;
        ready_alu_cmp_rs_idx = 'x;
        ready_mult_rs_idx = 'x;

        for (int unsigned i = 0; i < NUM_RES_STATIONS; ++i) // search for alu/cmp rs
        begin
            logic is_mult, is_ready; // hopefully the scope is limited to single iteration of for loop
            is_mult = (rs_curr[i].instr.r_type.opcode == op_reg) && (rs_curr[i].instr.r_type.funct7 == mult);
            is_ready = (valid_reg[rs_curr[i].ps1_s] & valid_reg[rs_curr[i].ps2_s] & rs_curr[i].busy);

            if (~is_mult & is_ready) // not mult
            begin
                exists_ready_alu_cmp_rs = 1'b1;
                ready_alu_cmp_rs = rs_curr[i];
                ready_alu_cmp_rs_idx = (RES_STATION_BITS)'(i);
                break;
            end
        end

        for (int unsigned i = 0; i < NUM_RES_STATIONS; ++i) // search for mult rs
        begin
            logic is_mult, is_ready;
            is_mult = (rs_curr[i].instr.r_type.opcode == op_reg) && (rs_curr[i].instr.r_type.funct7 == mult);
            is_ready = (valid_reg[rs_curr[i].ps1_s] & valid_reg[rs_curr[i].ps2_s] & rs_curr[i].busy); // busy indicates whether there is an unissued rs

            if (is_mult & is_ready) // not mult
            begin
                exists_ready_mult_rs = 1'b1;
                ready_mult_rs = rs_curr[i];
                ready_mult_rs_idx = (RES_STATION_BITS)'(i);
                break;
            end
        end
    end

    // search for ready functional units
    always_comb
    begin
        // default values
        exists_free_alu_cmp_fu = 1'b0;
        exists_free_mult_fu = 1'b0;
        free_alu_cmp_fu_idx = 'x;
        free_mult_fu_idx = 'x;

        for (int unsigned i = 0; i < NUM_ALU_CMP_UNITS; ++i)
        begin
            if (alu_cmp_busy[i] != 1'b1)
            begin
                exists_free_alu_cmp_fu = 1'b1;
                free_alu_cmp_fu_idx = ($clog2(NUM_ALU_CMP_UNITS))'(i);
                break;
            end
        end

        for (int unsigned i = 0; i < NUM_MULT_UNITS; ++i)
        begin
            if (mult_busy[i] != 1'b1)
            begin
                exists_free_mult_fu = 1'b1;
                free_mult_fu_idx = ($clog2(NUM_MULT_UNITS))'(i);
                break;
            end
        end
    end

    always_comb
    begin
        // default outputs
        rs_to_free = '0;
        for (int i = 0; i < NUM_ALU_CMP_UNITS; ++i)
        begin
            alu_cmp_input_data[i] = 'x;
            alu_cmp_start[i] = 1'b0;
        end
        for (int i = 0; i < NUM_MULT_UNITS; ++i)
        begin
            mult_input_data[i] = 'x;
            mult_start[i] = 1'b0;
        end

        // get register data
        ps1_s[0] = ready_alu_cmp_rs.ps1_s;
        ps2_s[0] = ready_alu_cmp_rs.ps2_s;
        ps1_s[1] = ready_mult_rs.ps1_s;
        ps2_s[1] = ready_mult_rs.ps2_s;

        // issue alu/cmp instr if there exists a match
        if (exists_free_alu_cmp_fu & exists_ready_alu_cmp_rs)
        begin
            alu_cmp_input_data[free_alu_cmp_fu_idx].instr = ready_alu_cmp_rs.instr;
            alu_cmp_input_data[free_alu_cmp_fu_idx].ps1_v = ps1_v[0];
            alu_cmp_input_data[free_alu_cmp_fu_idx].ps2_v = ps2_v[0];
            alu_cmp_input_data[free_alu_cmp_fu_idx].rvfi_data = ready_alu_cmp_rs.rvfi_data;
            // set read register data fields in rvfi_data
            alu_cmp_input_data[free_alu_cmp_fu_idx].rvfi_data.rs1_v = ps1_v[0];
            alu_cmp_input_data[free_alu_cmp_fu_idx].rvfi_data.rs2_v = ps2_v[0];

            alu_cmp_input_data[free_alu_cmp_fu_idx].rob_num = ready_alu_cmp_rs.rob_num;
            alu_cmp_input_data[free_alu_cmp_fu_idx].pd_s = ready_alu_cmp_rs.pd_s;
            alu_cmp_input_data[free_alu_cmp_fu_idx].pc = ready_alu_cmp_rs.pc; // need to store pc in rs_entry_t

            rs_to_free[ready_alu_cmp_rs_idx] = 1'b1;
            alu_cmp_start[free_alu_cmp_fu_idx] = 1'b1;
        end

        // issue mult instr if there exists a match
        if (exists_free_mult_fu & exists_ready_mult_rs)
        begin
            mult_input_data[free_mult_fu_idx].instr = ready_mult_rs.instr;
            mult_input_data[free_mult_fu_idx].ps1_v = ps1_v[1];
            mult_input_data[free_mult_fu_idx].ps2_v = ps2_v[1];
            mult_input_data[free_mult_fu_idx].rvfi_data = ready_mult_rs.rvfi_data;
            // set read register data fields in rvfi_data
            mult_input_data[free_mult_fu_idx].rvfi_data.rs1_v = ps1_v[1];
            mult_input_data[free_mult_fu_idx].rvfi_data.rs2_v = ps2_v[1];

            mult_input_data[free_mult_fu_idx].rob_num = ready_mult_rs.rob_num;
            mult_input_data[free_mult_fu_idx].pd_s = ready_mult_rs.pd_s;
            mult_input_data[free_mult_fu_idx].pc = ready_mult_rs.pc; // need to store pc in rs_entry_t

            rs_to_free[ready_mult_rs_idx] = 1'b1;
            mult_start[free_mult_fu_idx] = 1'b1;
        end
    end
endmodule
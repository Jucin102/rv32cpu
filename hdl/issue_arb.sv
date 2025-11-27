module issue_arb // assumes that NUM_ISSUE is 2
import rv32i_types::*;
(
    // no clk or rst because purely combinational
    input rs_entry_t rs_curr [NUM_RS_GROUP],
    input logic [31:0] ps1_v [NUM_ALU_MULT_ISSUE_GROUP],
    input logic [31:0] ps2_v [NUM_ALU_MULT_ISSUE_GROUP],
    input logic [NUM_PHYS_REGS-1:0] valid_reg,
    input logic [NUM_ALU_GROUP-1:0] alu_cmp_busy,
    input logic [NUM_MULT_GROUP-1:0] mult_busy,
    
    output logic [NUM_RS_GROUP-1:0] rs_to_free,
    output phys_reg ps1_s [NUM_ALU_MULT_ISSUE_GROUP],
    output phys_reg ps2_s [NUM_ALU_MULT_ISSUE_GROUP],
    output issue_fu_data_t alu_cmp_input_data[NUM_ALU_GROUP],
    output logic [NUM_ALU_GROUP-1:0] alu_cmp_start,
    output issue_fu_data_t mult_input_data[NUM_MULT_GROUP],
    output logic [NUM_MULT_GROUP-1:0] mult_start
);
    // will need to bitwise-OR free masks for RS with ALU instr and RS with MULT instr
    logic [NUM_RS_GROUP-1:0] alu_rs_to_free;
    logic [NUM_RS_GROUP-1:0] mult_rs_to_free;
    assign rs_to_free = alu_rs_to_free | mult_rs_to_free;

    // splitting up register ports between ALU and MULT units
    logic [31:0] alu_ps1_v [NUM_ALU_ISSUE_GROUP];
    logic [31:0] alu_ps2_v [NUM_ALU_ISSUE_GROUP];
    logic [31:0] mult_ps1_v [NUM_MULT_ISSUE_GROUP];
    logic [31:0] mult_ps2_v [NUM_MULT_ISSUE_GROUP];

    phys_reg alu_ps1_s [NUM_ALU_ISSUE_GROUP];
    phys_reg alu_ps2_s [NUM_ALU_ISSUE_GROUP];
    phys_reg mult_ps1_s [NUM_MULT_ISSUE_GROUP];
    phys_reg mult_ps2_s [NUM_MULT_ISSUE_GROUP];

    always_comb
    begin
        // assigning alu register ports
        for (int unsigned i = 0; i < NUM_ALU_ISSUE_GROUP; ++i)
        begin
            alu_ps1_v[i] = ps1_v[i];
            alu_ps2_v[i] = ps2_v[i];
            ps1_s[i] = alu_ps1_s[i];
            ps2_s[i] = alu_ps2_s[i];
        end

        // assigning mult register ports
        for (int unsigned i = NUM_ALU_ISSUE_GROUP; i < NUM_ALU_MULT_ISSUE_GROUP; ++i)
        begin
            mult_ps1_v[i - NUM_ALU_ISSUE_GROUP] = ps1_v[i];
            mult_ps2_v[i - NUM_ALU_ISSUE_GROUP] = ps2_v[i];
            ps1_s[i] = mult_ps1_s[i - NUM_ALU_ISSUE_GROUP];
            ps2_s[i] = mult_ps2_s[i - NUM_ALU_ISSUE_GROUP];
        end
    end

    // issuing ALU instr
    alu_issue_t alu_issue_arr[NUM_ALU_ISSUE_GROUP];
    
    // finding ready ALU instrs in RS
    always_comb
    begin
        logic [$clog2(NUM_ALU_ISSUE_GROUP) - 1 : 0] next_alu_issue_idx;
        next_alu_issue_idx = '0;

        //defaults 
        for (int unsigned i = 0; i < NUM_ALU_ISSUE_GROUP; ++i)
        begin
            alu_issue_arr[i].rs_valid = 1'b0;
            alu_issue_arr[i].ready_rs_idx = 'x;
        end

        for (int unsigned i = 0; i < NUM_RS_GROUP; ++i)
        begin
            logic is_mult, is_ready; // hopefully the scope is limited to single iteration of for loop
            is_mult = (rs_curr[i].instr.r_type.opcode == op_reg) && (rs_curr[i].instr.r_type.funct7 == mult);
            is_ready = (valid_reg[rs_curr[i].ps1_s] & valid_reg[rs_curr[i].ps2_s] & rs_curr[i].busy);

            if (~is_mult & is_ready) // not mult
            begin
                alu_issue_arr[next_alu_issue_idx].rs_valid = 1'b1;
                alu_issue_arr[next_alu_issue_idx].ready_rs_idx = ($clog2(NUM_RS_GROUP))'(i);

                if (next_alu_issue_idx == unsigned'((unsigned'($clog2(NUM_ALU_ISSUE_GROUP)))'(NUM_ALU_ISSUE_GROUP - unsigned'(1))))
                begin
                    break;
                end
                else
                begin
                    next_alu_issue_idx = unsigned'(next_alu_issue_idx + (unsigned'($clog2(NUM_ALU_ISSUE_GROUP)))'(unsigned'(1)));
                end
            end
        end
    end

    // finding ready ALU FUs 
    always_comb
    begin
        logic [$clog2(NUM_ALU_ISSUE_GROUP) - 1 : 0] next_alu_issue_idx;
        next_alu_issue_idx = '0;

        for (int unsigned i = 0; i < NUM_ALU_ISSUE_GROUP; ++i)
        begin
            alu_issue_arr[i].fu_valid = 1'b0;
            alu_issue_arr[i].ready_fu_idx = 'x;
        end

        for (int unsigned i = 0; i < NUM_ALU_GROUP; ++i)
        begin
            if (alu_cmp_busy[i] != 1'b1)
            begin
                alu_issue_arr[next_alu_issue_idx].fu_valid = 1'b1;
                alu_issue_arr[next_alu_issue_idx].ready_fu_idx = ($clog2(NUM_ALU_GROUP))'(i);

                if (next_alu_issue_idx == unsigned'((unsigned'($clog2(NUM_ALU_ISSUE_GROUP)))'(NUM_ALU_ISSUE_GROUP - unsigned'(1))))
                begin
                    break;
                end
                else
                begin
                    next_alu_issue_idx = next_alu_issue_idx + (unsigned'($clog2(NUM_ALU_ISSUE_GROUP)))'(unsigned'(1));
                end
            end
        end
    end

    // setting outputs to issue ALU instr
    always_comb
    begin
        // default outputs
        alu_rs_to_free = '0;
        for (int unsigned i = 0; i < NUM_ALU_GROUP; ++i)
        begin
            alu_cmp_input_data[i] = 'x;
            alu_cmp_start[i] = 1'b0;
        end
        for (int unsigned i = 0; i < NUM_ALU_ISSUE_GROUP; ++i)
        begin
            alu_ps1_s[i] = 'x;
            alu_ps2_s[i] = 'x;
        end

        // issuing instr
        for (int unsigned i = 0; i < NUM_ALU_ISSUE_GROUP; ++i)
        begin
            if ((alu_issue_arr[i].rs_valid == 1'b1) && (alu_issue_arr[i].fu_valid == 1'b1))
            begin
                // choosing registers to read
                alu_ps1_s[i] = rs_curr[alu_issue_arr[i].ready_rs_idx].ps1_s;
                alu_ps2_s[i] = rs_curr[alu_issue_arr[i].ready_rs_idx].ps2_s;

                alu_cmp_input_data[alu_issue_arr[i].ready_fu_idx].instr = rs_curr[alu_issue_arr[i].ready_rs_idx].instr;
                alu_cmp_input_data[alu_issue_arr[i].ready_fu_idx].ps1_v = alu_ps1_v[i];
                alu_cmp_input_data[alu_issue_arr[i].ready_fu_idx].ps2_v = alu_ps2_v[i];
                alu_cmp_input_data[alu_issue_arr[i].ready_fu_idx].rvfi_data = rs_curr[alu_issue_arr[i].ready_rs_idx].rvfi_data;
                // set read register data fields in rvfi_data
                alu_cmp_input_data[alu_issue_arr[i].ready_fu_idx].rvfi_data.rs1_v = alu_ps1_v[i];
                alu_cmp_input_data[alu_issue_arr[i].ready_fu_idx].rvfi_data.rs2_v = alu_ps2_v[i];

                alu_cmp_input_data[alu_issue_arr[i].ready_fu_idx].rob_num = rs_curr[alu_issue_arr[i].ready_rs_idx].rob_num;
                alu_cmp_input_data[alu_issue_arr[i].ready_fu_idx].pd_s = rs_curr[alu_issue_arr[i].ready_rs_idx].pd_s;
                alu_cmp_input_data[alu_issue_arr[i].ready_fu_idx].pc = rs_curr[alu_issue_arr[i].ready_rs_idx].pc; // need to store pc in rs_entry_t

                alu_cmp_input_data[alu_issue_arr[i].ready_fu_idx].br_taken_pred = rs_curr[alu_issue_arr[i].ready_rs_idx].br_taken_pred;

                alu_rs_to_free[alu_issue_arr[i].ready_rs_idx] = 1'b1;
                alu_cmp_start[alu_issue_arr[i].ready_fu_idx] = 1'b1;
            end
        end
    end

    // issuing MULT instr
    mult_issue_t mult_issue_arr[NUM_MULT_ISSUE_GROUP];
    
    // finding ready MULT instrs in RS
    always_comb
    begin
        logic [$clog2(NUM_MULT_ISSUE_GROUP) : 0] next_mult_issue_idx;
        next_mult_issue_idx = '0;

        for (int unsigned i = 0; i < NUM_MULT_ISSUE_GROUP; ++i)
        begin
            mult_issue_arr[i].rs_valid = 1'b0;
            mult_issue_arr[i].ready_rs_idx = 'x;
        end

        for (int unsigned i = 0; i < NUM_RS_GROUP; ++i)
        begin
            logic is_mult, is_ready; // hopefully the scope is limited to single iteration of for loop
            is_mult = (rs_curr[i].instr.r_type.opcode == op_reg) && (rs_curr[i].instr.r_type.funct7 == mult);
            is_ready = (valid_reg[rs_curr[i].ps1_s] & valid_reg[rs_curr[i].ps2_s] & rs_curr[i].busy);

            if (is_mult & is_ready) // not mult
            begin
                mult_issue_arr[next_mult_issue_idx].rs_valid = 1'b1;
                mult_issue_arr[next_mult_issue_idx].ready_rs_idx = ($clog2(NUM_RS_GROUP))'(i);

                if (next_mult_issue_idx == (unsigned'($clog2(NUM_MULT_ISSUE_GROUP)) + unsigned'(1))'(NUM_MULT_ISSUE_GROUP - unsigned'(1)))
                begin
                    break;
                end
                else
                begin
                    next_mult_issue_idx = next_mult_issue_idx + (unsigned'($clog2(NUM_MULT_ISSUE_GROUP)) + unsigned'(1))'(unsigned'(1));
                end
            end
        end
    end

    // finding ready MULT FUs 
    always_comb
    begin
        logic [$clog2(NUM_MULT_ISSUE_GROUP) : 0] next_mult_issue_idx;
        next_mult_issue_idx = '0;

        for (int unsigned i = 0; i < NUM_MULT_ISSUE_GROUP; ++i)
        begin
            mult_issue_arr[i].fu_valid = 1'b0;
            mult_issue_arr[i].ready_fu_idx = 'x;
        end

        for (int unsigned i = 0; i < NUM_MULT_GROUP; ++i)
        begin
            if (mult_busy[i] != 1'b1)
            begin
                mult_issue_arr[next_mult_issue_idx].fu_valid = 1'b1;
                mult_issue_arr[next_mult_issue_idx].ready_fu_idx = ($clog2(NUM_MULT_GROUP) + 1)'(i);

                if (next_mult_issue_idx == (unsigned'($clog2(NUM_MULT_ISSUE_GROUP)) + unsigned'(1))'(NUM_MULT_ISSUE_GROUP - unsigned'(1)))
                begin
                    break;
                end
                else
                begin
                    next_mult_issue_idx = next_mult_issue_idx + (unsigned'($clog2(NUM_MULT_ISSUE_GROUP)) + unsigned'(1))'(unsigned'(1));
                end
            end
        end
    end

    // setting outputs to issue MULT instr
    always_comb
    begin
        // default outputs
        mult_rs_to_free = '0;
        for (int unsigned i = 0; i < NUM_MULT_GROUP; ++i)
        begin
            mult_input_data[i] = 'x;
            mult_start[i] = 1'b0;
        end

        for(int i = 0; i < NUM_MULT_ISSUE_GROUP; i++) begin
            mult_ps1_s[i] = 'x;
            mult_ps2_s[i] = 'x;
        end

        // issuing instr
        for (int unsigned i = 0; i < NUM_MULT_ISSUE_GROUP; ++i)
        begin
            if ((mult_issue_arr[i].rs_valid == 1'b1) && (mult_issue_arr[i].fu_valid == 1'b1))
            begin
                // choosing registers to read
                mult_ps1_s[i] = rs_curr[mult_issue_arr[i].ready_rs_idx].ps1_s;
                mult_ps2_s[i] = rs_curr[mult_issue_arr[i].ready_rs_idx].ps2_s;

                mult_input_data[mult_issue_arr[i].ready_fu_idx].instr = rs_curr[mult_issue_arr[i].ready_rs_idx].instr;
                mult_input_data[mult_issue_arr[i].ready_fu_idx].ps1_v = mult_ps1_v[i];
                mult_input_data[mult_issue_arr[i].ready_fu_idx].ps2_v = mult_ps2_v[i];
                mult_input_data[mult_issue_arr[i].ready_fu_idx].rvfi_data = rs_curr[mult_issue_arr[i].ready_rs_idx].rvfi_data;
                // set read register data fields in rvfi_data
                mult_input_data[mult_issue_arr[i].ready_fu_idx].rvfi_data.rs1_v = mult_ps1_v[i];
                mult_input_data[mult_issue_arr[i].ready_fu_idx].rvfi_data.rs2_v = mult_ps2_v[i];

                mult_input_data[mult_issue_arr[i].ready_fu_idx].rob_num = rs_curr[mult_issue_arr[i].ready_rs_idx].rob_num;
                mult_input_data[mult_issue_arr[i].ready_fu_idx].pd_s = rs_curr[mult_issue_arr[i].ready_rs_idx].pd_s;
                mult_input_data[mult_issue_arr[i].ready_fu_idx].pc = rs_curr[mult_issue_arr[i].ready_rs_idx].pc; // need to store pc in rs_entry_t

                mult_rs_to_free[mult_issue_arr[i].ready_rs_idx] = 1'b1;
                mult_start[mult_issue_arr[i].ready_fu_idx] = 1'b1;

                // send br_taken_pred as 'x b/c not used for mult units
            end
        end
    end

endmodule
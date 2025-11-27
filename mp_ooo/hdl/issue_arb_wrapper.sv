module issue_arb_wrapper 
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
    generate for (genvar i = 0; i < signed'(NUM_RS_FU_GROUPS); ++i)
    begin : issue_arbs
        rs_entry_t rs_curr_group [NUM_RS_GROUP];
        logic [31:0] ps1_v_group [NUM_ALU_MULT_ISSUE_GROUP];
        logic [31:0] ps2_v_group [NUM_ALU_MULT_ISSUE_GROUP];

        phys_reg ps1_s_group [NUM_ALU_MULT_ISSUE_GROUP];
        phys_reg ps2_s_group [NUM_ALU_MULT_ISSUE_GROUP];
        issue_fu_data_t alu_cmp_input_data_group [NUM_ALU_GROUP];
        issue_fu_data_t mult_input_data_group [NUM_MULT_GROUP];

        issue_arb issue_arb_i (
            .rs_curr(rs_curr_group), // unpacked
            .ps1_v(ps1_v_group), // unpacked
            .ps2_v(ps2_v_group), // unpacked
            .valid_reg(valid_reg),
            .alu_cmp_busy(alu_cmp_busy[unsigned'(i)*NUM_ALU_GROUP +: NUM_ALU_GROUP]),
            .mult_busy(mult_busy[unsigned'(i)*NUM_MULT_GROUP +: NUM_MULT_GROUP]),

            .rs_to_free(rs_to_free[unsigned'(i)*NUM_RS_GROUP +: NUM_RS_GROUP]),
            .ps1_s(ps1_s_group), // unpacked
            .ps2_s(ps2_s_group), // unpacked
            .alu_cmp_input_data(alu_cmp_input_data_group), // unpacked
            .alu_cmp_start(alu_cmp_start[unsigned'(i)*NUM_ALU_GROUP +: NUM_ALU_GROUP]), 
            .mult_input_data(mult_input_data_group), // unpacked
            .mult_start(mult_start[unsigned'(i)*NUM_MULT_GROUP +: NUM_MULT_GROUP])
        );

        always_comb
        begin
            for (int unsigned j = 0; j < NUM_RS_GROUP; ++j)
            begin
                rs_curr_group[j] = rs_curr[unsigned'(i)*NUM_RS_GROUP + j];
            end

            for (int unsigned j = 0; j < NUM_ALU_MULT_ISSUE_GROUP; ++j)
            begin
                ps1_v_group[j] = ps1_v[unsigned'(i)*NUM_ALU_MULT_ISSUE_GROUP + j];
                ps2_v_group[j] = ps2_v[unsigned'(i)*NUM_ALU_MULT_ISSUE_GROUP + j];
                ps1_s[unsigned'(i)*NUM_ALU_MULT_ISSUE_GROUP + j] = ps1_s_group[j];
                ps2_s[unsigned'(i)*NUM_ALU_MULT_ISSUE_GROUP + j] = ps2_s_group[j];
            end

            for (int unsigned j = 0; j < NUM_ALU_GROUP; ++j)
            begin
                alu_cmp_input_data[unsigned'(i)*NUM_ALU_GROUP +j] = alu_cmp_input_data_group[j];
            end

            for (int unsigned j = 0; j < NUM_MULT_GROUP; ++j)
            begin
                mult_input_data[unsigned'(i)*NUM_MULT_GROUP + j] = mult_input_data_group[j];
            end
        end
    end
    endgenerate
endmodule
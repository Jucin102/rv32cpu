module alu_cmp_units
import rv32i_types::*;
(
    input logic clk, rst, branch_mispredict, // for now, use universal reset
    input issue_fu_data_t input_data[NUM_ALU_CMP_UNITS],
    input logic [NUM_ALU_CMP_UNITS-1:0] fu_start,
    input logic [NUM_ALU_CMP_UNITS-1:0] cdb_ack,

    output fu_cdb_data_t output_data[NUM_ALU_CMP_UNITS],
    output logic [NUM_ALU_CMP_UNITS-1:0] fu_busy,
    output logic [NUM_ALU_CMP_UNITS-1:0] fu_done
);

    
    generate for (genvar i = 0; i < signed'(NUM_ALU_CMP_UNITS); ++i)
    begin : alu_cmp_fus

        alu_cmp_fu alu_cmp_fu_i (
            .clk(clk),
            .rst(rst),
            .branch_mispredict(branch_mispredict),
            .input_data(input_data[i]),
            .fu_start(fu_start[i]),
            .cdb_ack(cdb_ack[i]),
            .output_data(output_data[i]),
            .fu_busy(fu_busy[i]),
            .fu_done(fu_done[i])
        );
    end
    endgenerate
endmodule
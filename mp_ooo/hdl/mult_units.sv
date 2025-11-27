module mult_units
import rv32i_types::*;
(
    input logic clk, rst, branch_mispredict, // for now, use universal reset
    input issue_fu_data_t input_data[NUM_MULT_UNITS],
    input logic [NUM_MULT_UNITS-1:0] fu_start,
    input logic [NUM_MULT_UNITS-1:0] cdb_ack,

    output fu_cdb_data_t output_data[NUM_MULT_UNITS],
    output logic [NUM_MULT_UNITS-1:0] fu_busy,
    output logic [NUM_MULT_UNITS-1:0] fu_done
);
    generate for (genvar i = 0; i < signed'(NUM_MULT_UNITS); ++i)
    begin : mult_fus
        mult_fu mult_fu_i (
            .clk(clk),
            .rst(rst),
            .branch_mispredict(branch_mispredict),
            .input_data(input_data[unsigned'(i)]),
            .fu_start(fu_start[unsigned'(i)]),
            .cdb_ack(cdb_ack[unsigned'(i)]),
            .output_data(output_data[unsigned'(i)]),
            .fu_busy(fu_busy[unsigned'(i)]),
            .fu_done(fu_done[unsigned'(i)])
        );
    end
    endgenerate
endmodule
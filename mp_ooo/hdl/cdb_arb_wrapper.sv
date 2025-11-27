module cdb_arb_wrapper // assumes that NUM_CDB = 1
import rv32i_types::*;
(
    input logic [NUM_ALU_CMP_UNITS-1:0] alu_cmp_done,
    input fu_cdb_data_t alu_cmp_output_data[NUM_ALU_CMP_UNITS],
    input logic [NUM_MULT_UNITS-1:0] mult_done,
    input fu_cdb_data_t mult_output_data[NUM_MULT_UNITS],

    output cdb_t cdb[NUM_ALU_MULT_CDB],
    output logic [NUM_ALU_CMP_UNITS-1:0] alu_cmp_ack,
    output logic [NUM_MULT_UNITS-1:0] mult_ack
);
    // split cdbs into alu and mult cdbs
    cdb_t alu_cdb[NUM_ALU_CDB];
    cdb_t mult_cdb[NUM_MULT_CDB];

    always_comb
    begin
        for (int unsigned i = 0; i < NUM_ALU_CDB; ++i)
        begin
            cdb[i] = alu_cdb[i];
        end

        for (int unsigned i = NUM_ALU_CDB; i < NUM_ALU_MULT_CDB; ++i)
        begin
            cdb[i] = mult_cdb[i - NUM_ALU_CDB];
        end
    end

    // handling alu cdbs
    generate for (genvar i = 0; i < signed'(NUM_ALU_CDB); ++i)
    begin : alu_cdbs
        fu_cdb_data_t cdb_input_data[NUM_ALU_PER_CDB];
        cdb_t cdb_arb_out;

        cdb_arb #(.NUM_FU(NUM_ALU_PER_CDB)) alu_cdb_arb_i(
            .fu_done(alu_cmp_done[i*NUM_ALU_PER_CDB +: NUM_ALU_PER_CDB]),
            .fu_output_data(cdb_input_data), // unpacked

            .cdb(cdb_arb_out), // unpacked
            .ack(alu_cmp_ack[i*NUM_ALU_PER_CDB +: NUM_ALU_PER_CDB])
        );

        always_comb
        begin
            for (int j = 0; j < NUM_ALU_PER_CDB; ++j)
            begin
                cdb_input_data[j] = alu_cmp_output_data[i*NUM_ALU_PER_CDB + j];
            end

            alu_cdb[i] = cdb_arb_out;
        end
    end
    endgenerate

    // handling mult cdbs
    generate for (genvar i = 0; i < signed'(NUM_MULT_CDB); ++i)
    begin : mult_cdbs
        fu_cdb_data_t cdb_input_data[NUM_MULT_PER_CDB];
        cdb_t cdb_arb_out;

        cdb_arb #(.NUM_FU(NUM_MULT_PER_CDB)) mult_cdb_arb_i(
            .fu_done(mult_done[unsigned'(i)*NUM_MULT_PER_CDB +: NUM_MULT_PER_CDB]),
            .fu_output_data(cdb_input_data), // unpacked

            .cdb(cdb_arb_out), // unpacked
            .ack(mult_ack[unsigned'(i)*NUM_MULT_PER_CDB +: NUM_MULT_PER_CDB])
        );

        always_comb
        begin
            for (int unsigned j = 0; j < NUM_MULT_PER_CDB; ++j)
            begin
                cdb_input_data[j] = mult_output_data[unsigned'(i)*NUM_MULT_PER_CDB + j];
            end

            mult_cdb[unsigned'(i)] = cdb_arb_out;
        end
    end
    endgenerate
endmodule
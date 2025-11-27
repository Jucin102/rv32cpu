module no_ss_cdb_arbiter // assumes that NUM_CDB = 1
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
    logic exists_ready_mult, exists_ready_alu_cmp;
    logic [$clog2(NUM_ALU_CMP_UNITS) - 1: 0] ready_alu_cmp_idx;
    logic [$clog2(NUM_MULT_UNITS) - 1: 0] ready_mult_idx;
    fu_cdb_data_t ready_alu_cmp_data, ready_mult_data;

    // search for ready mult fu and ready alu/cmp fu
    always_comb
    begin
        exists_ready_mult = 1'b0;
        exists_ready_alu_cmp = 1'b0;
        ready_alu_cmp_idx = 'x;
        ready_mult_idx = 'x;
        ready_alu_cmp_data = 'x;
        ready_mult_data = 'x;

        for (int unsigned i = 0; i < NUM_ALU_CMP_UNITS; ++i)
        begin
            if (alu_cmp_done[i])
            begin
                exists_ready_alu_cmp = 1'b1;
                ready_alu_cmp_idx = ($clog2(NUM_ALU_CMP_UNITS))'(i);
                ready_alu_cmp_data = alu_cmp_output_data[i];
                break;
            end
        end

        for (int unsigned i = 0; i < NUM_MULT_UNITS; ++i)
        begin
            if (mult_done[i])
            begin
                exists_ready_mult = 1'b1;
                ready_mult_idx = ($clog2(NUM_MULT_UNITS))'(i);
                ready_mult_data = mult_output_data[i];
                break;
            end
        end
    end

    // outputs
    always_comb
    begin
        // set default
        for (int i = 0; i < NUM_ALU_MULT_CDB; ++i)
        begin
            cdb[i] = 'x;
            cdb[i].br_en = 1'b0;
            cdb[i].valid = 1'b0;
        end
        alu_cmp_ack = '0;
        mult_ack = '0;

        if (exists_ready_mult)
        begin
            // setting cdb 
            cdb[0].valid = 1'b1;
            cdb[0].pd_s = ready_mult_data.pd_s;
            cdb[0].rob_num = ready_mult_data.rob_num;
            cdb[0].pd_v = ready_mult_data.pd_v;
            cdb[0].rvfi_data = ready_mult_data.rvfi_data;
            cdb[0].br_en = 1'b0;

            // set mult_ack
            mult_ack[ready_mult_idx] = 1'b1;
        end
        else if (exists_ready_alu_cmp)
        begin
            // setting cdb 
            cdb[0].valid = 1'b1;
            cdb[0].pd_s = ready_alu_cmp_data.pd_s;
            cdb[0].rob_num = ready_alu_cmp_data.rob_num;
            cdb[0].pd_v = ready_alu_cmp_data.pd_v;
            cdb[0].rvfi_data = ready_alu_cmp_data.rvfi_data;
            cdb[0].br_en = ready_alu_cmp_data.br_en;
            cdb[0].branch_pc = ready_alu_cmp_data.br_target;

            // set mult_ack
            alu_cmp_ack[ready_alu_cmp_idx] = 1'b1;
        end
    end
endmodule
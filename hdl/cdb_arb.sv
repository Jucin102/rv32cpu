module cdb_arb
import rv32i_types::*;
#(
    parameter NUM_FU = 2
)
(   
    input logic [NUM_FU - 1 : 0] fu_done,
    input fu_cdb_data_t fu_output_data[NUM_FU],

    output cdb_t cdb,
    output logic [NUM_FU - 1 : 0] ack
);
    logic exists_ready_fu;
    logic [$clog2(NUM_FU) - 1 : 0] ready_fu_idx;
 
    // search for ready fu
    always_comb
    begin
        exists_ready_fu = 1'b0;
        ready_fu_idx = 'x;

        for (int unsigned i = 0; i < NUM_FU; ++i)
        begin
            if (fu_done[i])
            begin
                exists_ready_fu = 1'b1;
                ready_fu_idx = ($clog2(NUM_FU))'(i);
                break;
            end
        end
    end

    // outputs
    always_comb
    begin
        // set default
        cdb = 'x;
        cdb.br_en = 1'b0;
        cdb.valid = 1'b0;

        ack = '0;

        if (exists_ready_fu)
        begin
            // setting cdb 
            cdb.valid = 1'b1;
            cdb.pd_s = fu_output_data[ready_fu_idx].pd_s;
            cdb.rob_num = fu_output_data[ready_fu_idx].rob_num;
            cdb.pd_v = fu_output_data[ready_fu_idx].pd_v;
            cdb.rvfi_data = fu_output_data[ready_fu_idx].rvfi_data;

            // set branch prediction related fields
            cdb.br_en = fu_output_data[ready_fu_idx].br_en;
            cdb.branch_pc = fu_output_data[ready_fu_idx].br_target;

            cdb.instr_pc = fu_output_data[ready_fu_idx].instr_pc;
            cdb.instr_is_br = fu_output_data[ready_fu_idx].instr_is_br;
            cdb.br_taken = fu_output_data[ready_fu_idx].br_taken;

            // set ack
            ack[ready_fu_idx] = 1'b1;
        end
    end
endmodule
module br_pred
import rv32i_types::*;
(
    input logic clk, rst,
    input logic [31:0] imem_addr,
    input cdb_t cdb[NUM_CDB],

    output logic [INSTR_FETCH_NUM - 1 : 0] br_taken // br_taken[0] corresponds w/ instr at imem_addr
);
    logic [NUM_BR_PRED - 1 : 0] inc, dec, pred;
    logic [$clog2(NUM_CDB) : 0] taken_count [NUM_BR_PRED];
    logic [$clog2(NUM_CDB) : 0] not_taken_count [NUM_BR_PRED];

    // defining counters
    generate for (genvar i = 0; i < NUM_BR_PRED; ++i)
    begin : br_pred_counters
        br_pred_counter br_pred_counter_i(
            .clk(clk),
            .rst(rst),
            .inc(inc[unsigned'(i)]),
            .dec(dec[unsigned'(i)]),

            .pred(pred[unsigned'(i)])
        );
    end
    endgenerate

    // calculating br_taken
    always_comb
    begin
        logic [31:0] instr_addr;

        br_taken = '0;

        for (int unsigned i = 0; i < SS_FACTOR; ++i)
        begin
            instr_addr = imem_addr + 4*i;
            br_taken[i] = pred[instr_addr[2 +: NUM_BR_PRED_BITS]]; // start at 2 because bits 1 and 0 are always 0 because of instr address alignment
        end
    end

    // calculating inc and dec
    always_comb
    begin
        logic [31:0] instr_pc;
        inc = '0;
        dec = '0;
        for (int i = 0; i < NUM_BR_PRED; ++i)
        begin
            taken_count[i] = '0;
            not_taken_count[i] = '0;
        end

        for (int unsigned i = 0; i < NUM_CDB; ++i)
        begin
            instr_pc = cdb[i].instr_pc;
            if (cdb[i].instr_is_br == 1'b1 && cdb[i].br_taken == 1'b1)
            begin
                taken_count[instr_pc[2 +: NUM_BR_PRED_BITS]] = taken_count[instr_pc[2 +: NUM_BR_PRED_BITS]] + ($clog2(NUM_CDB) + 1)'(1);
            end
            else if (cdb[i].instr_is_br == 1'b1 && cdb[i].br_taken == 1'b0)
            begin
                not_taken_count[instr_pc[2 +: NUM_BR_PRED_BITS]] = not_taken_count[instr_pc[2 +: NUM_BR_PRED_BITS]] + ($clog2(NUM_CDB) + 1)'(1);
            end
        end

        for (int i = 0; i < NUM_BR_PRED; ++i)
        begin
            if (taken_count[i] > not_taken_count[i])
            begin
                inc[i] = 1'b1;
            end
            else if (not_taken_count[i] > taken_count[i])
            begin
                dec[i] = 1'b1;
            end
        end
    end
endmodule
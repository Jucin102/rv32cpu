module store_queue 
import rv32i_types::*;
#(
    parameter WIDTH = 32,
    parameter DEPTH = NUM_LSQ_ENTRIES,
    parameter DEPTH_BITS = $clog2(DEPTH),
    parameter SS_BITS = SS_FACTOR_BITS,
    parameter SS = SS_FACTOR
)
(
    input logic clk, rst, mispredict,
    input logic [SS_BITS:0] dispatch_push, 
    input logic arbiter_pop,
    input lsq_entry_t dispatch_store_load_input[SS],
    output lsq_entry_t arbiter_store_load_output,
    output logic [DEPTH_BITS : 0] lsq_free,
    output logic lsq_empty,

    output logic exists_store_dependency,
    output rob_num_t store_dependency
);

    lsq_entry_t lsq_queue[DEPTH];
    logic [DEPTH_BITS : 0] head, tail, tail_minus_one;
    logic [DEPTH_BITS:0] ligma_size;

    // Flush queue on reset or mispredict
    always_ff @(posedge clk) begin
        if(rst || mispredict) begin
            for(int i = 0; i < DEPTH; i++) begin
                lsq_queue[i] <= '0;
            end
            head <= '0;
            tail <= '0;
            tail_minus_one <= '1;
            ligma_size <= '0;
        end else begin

            // New load/store instructions from 
            if(dispatch_push > (SS_BITS + 1)'(unsigned'(0)) && ligma_size != unsigned'((DEPTH_BITS + unsigned'(1))'(DEPTH))) begin
                for(int unsigned i = 0; i < SS; i++) begin
                    if((SS_BITS + unsigned'(1))'(i) < dispatch_push) begin
                        lsq_queue[(DEPTH_BITS)'(tail[DEPTH_BITS - 1:0] + i)] <= dispatch_store_load_input[i];
                    end
                end
                tail <= tail + dispatch_push;
                tail_minus_one <= tail_minus_one + dispatch_push;
            end

            // Outgoing load/store instructions requested by arbiter
            if(arbiter_pop > 0 && |ligma_size != 1'b0) begin
                head <= head + arbiter_pop;
            end

            ligma_size <= ligma_size + dispatch_push - arbiter_pop; 
        end
    end
    
    always_comb begin
        // Popped value
        arbiter_store_load_output = lsq_queue[DEPTH_BITS'(head[DEPTH_BITS - 1:0])];
    end

    always_comb begin
        lsq_free = (DEPTH_BITS + unsigned'(1))'(DEPTH - ligma_size);
        lsq_empty = (ligma_size == '0) ? 1'b1 : 1'b0;
    end

    // calculating exists_store_dependency
    always_comb
    begin
        exists_store_dependency = (!((ligma_size == '0) || (ligma_size == (DEPTH_BITS + unsigned'(1))'(1) && arbiter_pop == 1'b1)));
    end

    // calculate store dependency rob number
    always_comb
    begin
        // if ((DEPTH_BITS)'(tail) == '0) // deal with wrap around (probably overkill)
        // begin
        //     // store_dependency = lsq_queue[(DEPTH_BITS)'(int'(DEPTH) - 1)].rob_num;
        //     store_dependency = lsq_queue[(DEPTH_BITS)'(1)].rob_num; // assumes that DEPTH is a power of 2 always
        // end
        // else
        // begin
        //     store_dependency = lsq_queue[(DEPTH_BITS)'((DEPTH_BITS)'(tail) - 1)].rob_num;
        // end
        store_dependency = lsq_queue[(DEPTH_BITS)'(tail_minus_one)].rob_num;
    end

endmodule : store_queue
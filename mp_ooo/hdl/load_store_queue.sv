module load_store_queue 
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
    output logic lsq_empty
);

    lsq_entry_t lsq_queue[DEPTH];
    logic [DEPTH_BITS : 0] head, tail;
    logic [DEPTH_BITS:0] ligma_size;

    // Flush queue on reset or mispredict
    always_ff @(posedge clk) begin
        if(rst || mispredict) begin
            for(int i = 0; i < DEPTH; i++) begin
                lsq_queue[i] <= '0;
            end
            head <= '0;
            tail <= '0;
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

endmodule : load_store_queue
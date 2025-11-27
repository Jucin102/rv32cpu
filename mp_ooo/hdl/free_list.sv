module free_list
import rv32i_types::*;
#(
    parameter SS = SS_FACTOR,
    parameter WIDTH = NUM_PHYS_REGS_BITS,
    parameter DEPTH = NUM_PHYS_REGS - 32,
    parameter DEPTH_BITS = $clog2(DEPTH)
)
(
    input logic clk, rst,
    input phys_reg freed_register[SS],
    input logic[SS_FACTOR_BITS : 0] rrf_push, 
    input logic[SS_FACTOR_BITS : 0] dispatch_pop,  
    input logic mispredict,
    output phys_reg used_register[SS],
    output logic[DEPTH_BITS:0] num_free_regs
);

    logic [WIDTH - 1:0] free_list_queue[DEPTH];
    logic [DEPTH_BITS:0] head, tail;
    logic [DEPTH_BITS:0] ligma_size; 
    logic [DEPTH_BITS:0] tail_mispredict;
    
    always_ff @(posedge clk) begin
        // Initialize to full with all the unassigned physical register values
        if(rst) begin
            for(int unsigned i = 0; i < DEPTH; i++) begin
                free_list_queue[i] <= (WIDTH)'(i + 32);
            end
            head <= '0;
            tail <= {{1'b1}, {(DEPTH_BITS){1'b0}}};
            ligma_size <= {{1'b1}, {(DEPTH_BITS){1'b0}}};
        end 
        // On mispredict, the size should be full since the head and tail are pointed to the same spot. The missing regs between head and tail should be the in flight regs in uncommitted ROB entries.
        // Gotta change this for SS since we can commit some, but for now this should work.
        else if(mispredict) begin
            if(rrf_push > 0) begin
                for(int unsigned i = 0; i < SS; i++) begin
                    if((SS_FACTOR_BITS + unsigned'(1))'(i) < rrf_push) begin
                        free_list_queue[tail[DEPTH_BITS - 1:0] + DEPTH_BITS'(i)] <= freed_register[i];
                    end
                end
            end
            ligma_size <= {{1'b1}, {(DEPTH_BITS){1'b0}}};
            tail <= tail_mispredict;
            head <= {{tail_mispredict[DEPTH_BITS] + 1'b1}, {tail_mispredict[DEPTH_BITS-1:0]}};
        end 
        else begin
            // Update tail and queue when pushing requested by rrf
            if(rrf_push > 0) begin
                for(int unsigned i = 0; i < SS; i++) begin
                    if((SS_FACTOR_BITS + unsigned'(1))'(i) < rrf_push) begin
                        free_list_queue[tail[DEPTH_BITS - 1:0] + DEPTH_BITS'(i)] <= freed_register[i];
                    end
                end
                tail <= tail + rrf_push;
            end
            // Update head and queue when popping requested by dispatch to get currently free registers
            if(dispatch_pop > 0 && ligma_size > 0) begin
                head <= head + dispatch_pop;
            end

            ligma_size <= ligma_size + rrf_push - dispatch_pop;
        end
    end
    
    always_comb begin
        // New used register for dispatch
        for(int unsigned i = 0; i < SS; i++) begin
            used_register[i] = free_list_queue[DEPTH_BITS'(head[DEPTH_BITS - 1:0] + i)];
        end

        // Check size
        num_free_regs = ligma_size;
        tail_mispredict = tail + rrf_push;
    end

endmodule
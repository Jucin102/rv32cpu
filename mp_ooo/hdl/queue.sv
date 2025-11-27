module queue 
import rv32i_types::*;
#(
    parameter WIDTH = INSTR_FETCH_NUM * $bits(pc_instr_t),
    parameter DEPTH = 8,
    parameter DEPTH_BITS = $clog2(DEPTH)
)
(
    input logic clk, rst, mispredict,
    input logic [WIDTH - 1: 0] real_input_ligma,
    output logic [WIDTH - 1: 0] real_output_ligma,
    input logic push, pop,  
    output logic full, empty
);

    logic [DEPTH-1: 0][WIDTH-1: 0] ligma_queue;
    logic [DEPTH_BITS : 0] head, tail;
    logic [DEPTH_BITS : 0] const_1d, const_0d;
    // DEPTH width mismatch when comparing with tail

    always_comb begin
        const_1d = {{(DEPTH_BITS){1'b0}}, {1'b1}};
        const_0d = {{(DEPTH_BITS){1'b0}}, {1'b0}};
    end
    
    always_ff @(posedge clk) begin
        if(rst || mispredict) begin
            for(int i = 0; i < DEPTH; i++) begin
                ligma_queue[i] <= '0;
            end
            head <= '0;
            tail <= '0;
        end else begin
            // Update tail and queue when pushing
            if(push && !full) begin
                ligma_queue[tail[DEPTH_BITS - 1 : 0]] <= real_input_ligma;
                tail <= tail + const_1d;
            end
            // Update head and queue when popping
            if(pop && !empty) begin
                head <= head + const_1d;
            end
        end
    end
    
    always_comb begin
        // Set output signals/data
        real_output_ligma = ligma_queue[head[DEPTH_BITS - 1 : 0]];

        full = (
            tail[DEPTH_BITS - 1 :
             0] == head[DEPTH_BITS - 1 : 0] &&
            tail[DEPTH_BITS] != head[DEPTH_BITS]
        );
        empty = tail == head;

    end

endmodule : queue
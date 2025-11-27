module branch_queue
import rv32i_types ::*; 
#(
    parameter SS = SS_FACTOR,
    parameter SS_BITS = SS_FACTOR_BITS,
    parameter WIDTH = $bits(brq_entry_t),
    parameter DEPTH = NUM_BRANCH,
    parameter DEPTH_BITS = NUM_BRANCH_BITS
)
(
    input logic clk, rst, mispredict,
    input brq_entry_t brq_entry[SS],
    input cdb_t cdb_entries[NUM_CDB],
    input logic [SS_BITS : 0] brq_push,
    input logic [SS_BITS:0] commit_cnt,
    input logic [NUM_ROB_ENTRIES_BITS-1:0] rob_number_br_queue,
    input logic br_queue_mask[SS],
    output brq_entry_t br_PC,
    output logic [DEPTH_BITS:0] num_free_brq_entries
);

    brq_entry_t branch_queue_queue[DEPTH];
    logic [SS:0] branch_cnt;
    logic [DEPTH_BITS:0] head, tail;
    logic [DEPTH_BITS:0] const_1d, const_0d;
    logic [DEPTH_BITS:0] ligma_size;
    logic [NUM_ROB_ENTRIES_BITS - 1: 0] mispredict_rob_num;
    
    always_ff @(posedge clk) begin
        // Branch queue reset and mispredict flushes
        if(rst || mispredict) begin
            for(int unsigned i = 0; i < DEPTH; i++) begin
                branch_queue_queue[i] <= '0;
            end
            head <= '0;
            tail <= '0;
            ligma_size <= '0;
        end 
        else begin
            // We push if dispatch pushes in a branch inst and queue is not full.
            if(ligma_size != unsigned'((DEPTH_BITS + unsigned'(1))'(DEPTH))) begin
                for(int unsigned i = 0; i < SS; i++) begin
                    if((unsigned'($bits(brq_push)))'(i) < brq_push) begin
                        branch_queue_queue[tail[DEPTH_BITS - 1:0] + DEPTH_BITS'(i)] <= brq_entry[i];
                    end
                end
                tail <= tail + brq_push;
            end

            // Update head and queue when popping.
            if(|ligma_size != 1'b0) begin
                head <= head + branch_cnt;
            end

            // Check if we can update any brq entry
            for(int unsigned i = 0; i < NUM_CDB; i++) begin
                for (int unsigned j = 0; j < DEPTH; ++j)
                begin
                    if ((cdb_entries[i].valid == 1'b1) && (cdb_entries[i].rob_num == branch_queue_queue[j].rob_idx))
                    begin
                        branch_queue_queue[j].branch_pc <= cdb_entries[i].branch_pc;
                    end
                end
            end

            ligma_size <= ligma_size + brq_push - branch_cnt;
        end
    end
    
    // Branch
    always_comb begin
        branch_cnt = '0;
        mispredict_rob_num = 'x;
        br_PC = 'x;
        

        // Check if branch queue has any mispredict
        for (int unsigned i = 0; i < SS; ++i)
        begin
            if(br_queue_mask[i] == 1'b1) begin
                mispredict_rob_num = NUM_ROB_ENTRIES_BITS'(rob_number_br_queue + i);
            end
        end

        for(int unsigned i = 0; i < SS; ++i)
        begin
            if (i < 32'(ligma_size) && mispredict_rob_num == branch_queue_queue[DEPTH_BITS'(head + i)].rob_idx) begin
                br_PC = branch_queue_queue[DEPTH_BITS'(head + i)];
            end
        end


        // If no mispredict
        for(int unsigned i = 0; i < SS; i++) begin
            for (int unsigned j = 0; j < SS; ++j)
            begin
                if(i < 32'(commit_cnt) && j < 32'(ligma_size))
                begin
                    if (NUM_ROB_ENTRIES_BITS'(rob_number_br_queue + i) == branch_queue_queue[DEPTH_BITS'(head + j)].rob_idx)
                    begin
                        branch_cnt = branch_cnt + (SS)'(unsigned'(1));
                    end
                end
            end
        end
    end

    // Queue state
    always_comb begin
        num_free_brq_entries = (DEPTH_BITS + 1)'(DEPTH - ligma_size);
    end

endmodule
module rob
import rv32i_types ::*; 
#(
    parameter SS = SS_FACTOR,
    parameter SS_BITS = SS_FACTOR_BITS,
    parameter WIDTH = $bits(rob_entry_t),
    parameter DEPTH = NUM_ROB_ENTRIES,
    parameter DEPTH_BITS = NUM_ROB_ENTRIES_BITS
)
(
    input logic clk, rst,
    input rob_entry_t dispatch_input[SS],
    input cdb_t cdb_entries[NUM_CDB],
    input logic [SS_BITS : 0] dispatch_push,
    output logic [SS_BITS : 0] commit_cnt,
    output arch_reg rrf_arch_reg[SS],
    output phys_reg rrf_phys_reg[SS],
    output logic [DEPTH_BITS:0] num_free_regs,
    output rvfi_data_t rvfi_rob_output[SS],
    output logic [DEPTH_BITS-1:0] rob_number_head,
    output logic [DEPTH_BITS - 1:0] rob_number_tail,
    output logic br_queue_mask [SS],
    output logic mispredict
);

    rob_entry_t rob_queue[DEPTH];
    logic [DEPTH_BITS:0] head, tail;
    // logic [DEPTH_BITS:0] count_pd;
    logic [DEPTH_BITS:0] const_1d, const_0d;
    logic [DEPTH_BITS:0] ligma_size;
    logic [63:0] order, order_next;

    // DEPTH width mismatch when comparing with tail
    // always_comb begin
    //     const_1d = {{(DEPTH_BITS){1'b0}}, {1'b1}};
    //     const_0d = {{(DEPTH_BITS){1'b0}}, {1'b0}};
    // end
    
    always_ff @(posedge clk) begin
        // ROB resets everything to 0 on reset or mispredict
        if(rst) begin
            for(int unsigned i = 0; i < DEPTH; i++) begin
                rob_queue[i] <= '0;
            end
            head <= '0;
            tail <= '0;
            ligma_size <= '0;
            order <= '0;
        end 

        // Same as rst, but don't reset order
        else if(mispredict) begin
           for(int unsigned i = 0; i < DEPTH; i++) begin
                rob_queue[i] <= '0;
            end
            head <= '0;
            tail <= '0;
            ligma_size <= '0;
            order <= order_next;
        end
        else begin
            // We push if dispatch pushes in an ROB entry and our ROB entry is not full.
            if(dispatch_push > (SS_BITS + unsigned'(1))'(0) && ligma_size != unsigned'((DEPTH_BITS + unsigned'(1))'(DEPTH))) begin
                for(int unsigned i = 0; i < SS; i++) begin
                    if((SS_BITS + unsigned'(1))'(i) < dispatch_push) begin
                        rob_queue[tail[DEPTH_BITS - 1:0] + DEPTH_BITS'(i)] <= dispatch_input[i];
                    end
                end
                tail <= tail + dispatch_push;
            end

            // Update head and queue when popping. We pop if we commit the head entry to rrf.
            if(|ligma_size != 1'b0) begin
                head <= head + commit_cnt;
            end

            // Check if we can update any valid rob
            for(int unsigned i = 0; i < NUM_CDB; i++) begin
                if(cdb_entries[i].valid) begin
                    rob_queue[cdb_entries[i].rob_num].valid <= 1'b1;
                    rob_queue[cdb_entries[i].rob_num].rvfi_data <= cdb_entries[i].rvfi_data;

                    // Branch bit update, work on later
                    rob_queue[cdb_entries[i].rob_num].br <= cdb_entries[i].br_en;
                end
            end

            ligma_size <= ligma_size + dispatch_push - commit_cnt;
            order <= order_next;
        end
    end
    
    // Commit output logic
    always_comb begin
        commit_cnt = '0;
        mispredict = '0;
        for(int unsigned i = 0; i < SS; i++) begin
            rrf_arch_reg[i] = '0;
            rrf_phys_reg[i] = '0;
            br_queue_mask[i] = 1'b0;
        end

        // Check if head is valid and rob is not empty, then we update rrf with new entry.
        for(int unsigned i = 0; i < SS; i++) begin
            if(rob_queue[head[DEPTH_BITS - 1:0] + DEPTH_BITS'(i)].valid && (DEPTH_BITS + 1)'(ligma_size - i) > 0) begin

                // Send arch_reg_d and phys_reg_d = 0 for branch instructions. rrf shouldn't be updated since branch doesn't use phys/arch regs
                // mispredict important, universal signal to all other modules to perform branch mispredict cleanup
                if(rob_queue[DEPTH_BITS'(head[DEPTH_BITS - 1:0] + i)].br) begin
                    mispredict = 1'b1;
                    rrf_arch_reg[i] = rob_queue[head[DEPTH_BITS - 1:0] + DEPTH_BITS'(i)].arch_reg_d;
                    rrf_phys_reg[i] = rob_queue[head[DEPTH_BITS - 1:0] + DEPTH_BITS'(i)].phys_reg_d;
                    br_queue_mask[i] = 1'b1;
                    commit_cnt = commit_cnt + (SS_BITS + unsigned'(1))'(unsigned'(1));
                    break;
                end
                // No branch related issues here
                else begin
                    rrf_arch_reg[i] = rob_queue[head[DEPTH_BITS - 1:0] + DEPTH_BITS'(i)].arch_reg_d;
                    rrf_phys_reg[i] = rob_queue[head[DEPTH_BITS - 1:0] + DEPTH_BITS'(i)].phys_reg_d;
                    br_queue_mask[i] = 1'b0;
                    commit_cnt = commit_cnt + (SS_BITS + unsigned'(1))'(unsigned'(1));
                end
            end
            else begin
                break; 
            end
        end
    end

    // Queue state
    always_comb begin
        num_free_regs = (DEPTH_BITS + 1)'(DEPTH - ligma_size);
        rob_number_tail = tail[DEPTH_BITS - 1:0];
        rob_number_head = head[DEPTH_BITS - 1:0];
    end

    // RVFI
    always_comb begin
        order_next = order;
        for(int unsigned i = 0; i < SS; i++) begin
            rvfi_rob_output[i] = '0;
            if((SS_BITS + unsigned'(1))'(i) < commit_cnt) begin
                rvfi_rob_output[i] = rob_queue[head[DEPTH_BITS - 1:0] + DEPTH_BITS'(i)].rvfi_data;
                rvfi_rob_output[i].valid = 1'b1;
                rvfi_rob_output[i].order = order_next;
                order_next = order_next + 'd1;
            end
        end
    end

    //Debug

    // always_comb begin
    //     count_pd = '0;
    //     for(int unsigned i = 0; i < 64; i++) begin
    //         if(i >= head && i < tail && rob_queue[i].phys_reg_d != 0) begin
    //             count_pd += 'd1;
    //         end
    //     end
    // end

endmodule

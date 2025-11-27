module load_rs
import rv32i_types::*;
(
    input logic clk, rst,
    
    // I/O with rename/dispatch
    input load_rs_entry_t input_entries[SS_FACTOR],
    input logic [SS_FACTOR_BITS : 0] num_push,
    output logic [SS_FACTOR_BITS : 0] push_limit,

    // I/O with CDB, reg file, store queue, etc
    input logic [NUM_PHYS_REGS - 1 : 0] valid_reg,
    input cdb_t store_load_cdb,
    input rob_num_t store_dependency,
    input logic exists_store_dependency,
    input logic mispredict,

    // I/O with mem arbiter
    input logic free,
    input logic[LOAD_RS_BITS - 1 : 0] free_idx,
    output load_rs_entry_t output_entries[NUM_LOAD_RS]
);
    // initialization
    load_rs_entry_t input_entries_local[NUM_LOAD_RS];
    logic [NUM_LOAD_RS - 1 : 0] we;
    logic [NUM_LOAD_RS - 1 : 0] free_arr;

    // bookkeeping
    logic [NUM_LOAD_RS - 1 : 0] mask, mask_next;
    logic [LOAD_RS_BITS : 0] num_not_busy, num_not_busy_next;
    logic [LOAD_RS_BITS - 1 : 0] not_busy_idx [SS_FACTOR];
    logic [LOAD_RS_BITS - 1 : 0] not_busy_idx_next [SS_FACTOR];
    
    generate for (genvar i = 0; i < signed'(NUM_LOAD_RS); ++i)
    begin
        load_rs_entry load_rs_entry_i(
            .clk(clk),
            .rst(rst | mispredict | free_arr[i]),

            .input_entry(input_entries_local[i]),
            .valid_reg(valid_reg),
            .store_load_cdb(store_load_cdb),
            .we(we[i]),

            .output_entry(output_entries[i])
        );
    end
    endgenerate

    // // setting push_limit
    // always_comb
    // begin
    //     push_limit = '0;
    //     not_busy_count = '0;

    //     for (int i = 0; i < NUM_LOAD_RS; ++i)
    //     begin
    //         if (output_entries[i].state == EMPTY)
    //         begin
    //             not_busy_count = not_busy_count + (LOAD_RS_BITS + unsigned'(1))'(1);
    //         end
    //     end

    //     push_limit = (SS_FACTOR_BITS + unsigned'(1))'(not_busy_count);
    // end

    // setting bookkeeping information
    always_comb
    begin
        if (rst | mispredict)
        begin
            mask_next = '0;
        end
        else
        begin
            mask_next = mask;
            if (free)
            begin
                mask_next[free_idx] = 1'b0;
            end

            for (int unsigned i = 0; i < SS_FACTOR; ++i)
            begin
                if ((SS_FACTOR_BITS + unsigned'(1))'(i) < num_push)
                begin
                    mask_next[not_busy_idx[(SS_FACTOR_BITS)'(i)]] = 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk)
    begin
        mask <= mask_next;
    end

    always_comb
    begin
        num_not_busy_next = (LOAD_RS_BITS + unsigned'(1))'(unsigned'($countones(~mask_next)));
    end

    always_ff @(posedge clk)
    begin
        num_not_busy <= num_not_busy_next;
    end

    always_comb
    begin
        logic [SS_FACTOR_BITS : 0] num_not_busy_found;
        // default
        num_not_busy_found = '0;
        for (int unsigned i = 0; i < SS_FACTOR; ++i)
        begin
            not_busy_idx_next[(SS_FACTOR_BITS)'(i)] = 'x; 
        end


        for (int unsigned i = 0; i < NUM_LOAD_RS; ++i)
        begin
            if (mask_next[(LOAD_RS_BITS)'(i)] == 1'b0 && num_not_busy_found < unsigned'((SS_FACTOR_BITS + unsigned'(1))'(unsigned'(SS_FACTOR))))
            begin
                not_busy_idx_next[(SS_FACTOR_BITS)'(num_not_busy_found)] = (LOAD_RS_BITS)'(i);
                num_not_busy_found = num_not_busy_found + (SS_FACTOR_BITS + unsigned'(1))'(1);
            end
        end
    end

    always_ff @(posedge clk)
    begin
        not_busy_idx <= not_busy_idx_next;
    end

    // I/O with load_rs_entries
    always_comb // free_arr
    begin
        free_arr = '0;
        if (free)
        begin
            free_arr[free_idx] = 1'b1;
        end
    end

    always_comb // input_entries and we
    begin
        // defaults
        we = '0;
        for (int unsigned i = 0; i < NUM_LOAD_RS; ++i)
        begin
            input_entries_local[(LOAD_RS_BITS)'(i)] = 'x;
        end

        for (int unsigned i = 0; i < SS_FACTOR; ++i)
        begin
            if ((SS_FACTOR_BITS + unsigned'(1))'(i) < num_push)
            begin
                input_entries_local[not_busy_idx[(SS_FACTOR_BITS)'(i)]] = input_entries[(SS_FACTOR_BITS)'(i)];
                if (exists_store_dependency)
                begin
                    input_entries_local[not_busy_idx[(SS_FACTOR_BITS)'(i)]].state = WAIT_FOR_STORE;
                    input_entries_local[not_busy_idx[(SS_FACTOR_BITS)'(i)]].store_dependency = store_dependency;
                end
                else
                begin
                    input_entries_local[not_busy_idx[(SS_FACTOR_BITS)'(i)]].state = WAIT_FOR_REG;
                end

                we[not_busy_idx[(SS_FACTOR_BITS)'(i)]] = 1'b1;
            end
        end
    end

    // output
    always_comb
    begin
        logic [LOAD_RS_BITS : 0] min; // assume that number of rs > ss factor
        min = ((LOAD_RS_BITS + unsigned'(1))'(SS_FACTOR) < num_not_busy) ? (LOAD_RS_BITS + unsigned'(1))'(SS_FACTOR) : num_not_busy;

        push_limit = (SS_FACTOR_BITS + unsigned'(1))'(min);
    end
endmodule
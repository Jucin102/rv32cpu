module cacheline_adaptor
import rv32i_types::*;
(
    input   logic               clk,
    input   logic               rst,

    // i-cache <-> adaptor signals
    input  logic   [31:0]      i_addr,
    input  logic               i_read,
    output   logic   [255:0]   i_rdata,
    output   logic             i_resp,

    // d-cache <-> adaptor signals
    input  logic   [31:0]      d_addr,
    input  logic               d_read,
    input  logic               d_write,
    output   logic   [255:0]   d_rdata,
    input  logic   [255:0]     d_wdata,
    output   logic             d_resp,

    // adaptor <-> mem signals
    output logic   [31:0]      mem_addr,
    output logic               mem_read,
    output logic               mem_write,
    output logic   [63:0]      mem_wdata,
    input logic                mem_ready,

    input logic   [31:0]       mem_raddr,
    input logic   [63:0]       mem_rdata,
    input logic                mem_rvalid
);

    enum logic [0 : 0] {DECIDE, WAIT_FOR_RESP} state, state_next; // DECIDE = deciding instr or data / idle, WAIT = waiting to give response to cache
    enum logic [0 : 0] {STORE, LOAD} transaction, transaction_next;
    enum logic [0 : 0] {I_CACHE, D_CACHE} cache_choice, cache_choice_next;
    logic [2 : 0] transaction_counter, transaction_counter_next;
    logic [63 : 0] d_wdata_split [4]; // splitting write data into 4 chunks of 64 bits each
    logic [63 : 0] mem_read_buffer [3]; // loading 3 bursts, 4th burst is read combinationally directly from mem
    // logic [31 : 0] i_addr_reg;

    always_ff @(posedge clk) begin
        if (rst) begin // deleted mispredict 
            transaction_counter <= '0;
            state <= DECIDE;
            transaction <= LOAD;
            cache_choice <= D_CACHE;
            for(int i = 0; i < 3; i++) begin
                mem_read_buffer[i] <= '0;
            end
            // i_addr_reg <= '0;
        end else begin
            transaction_counter <= transaction_counter_next;
            state <= state_next;
            transaction <= transaction_next;
            cache_choice <= cache_choice_next;
            
            // mem_read_buffer
            if (mem_rvalid) begin
                mem_read_buffer[transaction_counter] <= mem_rdata;
            end

            // if(mem_read) begin
            //     i_addr_reg <= mem_addr;
            // end
        end
    end

    // transaction
    always_comb begin
        // default state variables
        transaction_next = transaction;
        cache_choice_next = cache_choice;
        state_next = state;
        transaction_counter_next = transaction_counter;

        // default outputs to memory
        mem_addr = '0;
        mem_read = '0;
        mem_write = '0;
        mem_wdata = '0;

        // default outputs to caches, data in another block
        i_resp = '0;
        d_resp = '0;

        // default 256 bit splits
        d_wdata_split[0] = d_wdata[63 : 0];
        d_wdata_split[1] = d_wdata[127 : 64];
        d_wdata_split[2] = d_wdata[191 : 128];
        d_wdata_split[3] = d_wdata[255 : 192];

        if (state == DECIDE) begin // check if we need to begin transaction
            if (i_read && !(d_read || d_write) && mem_ready) begin // pick icache
                cache_choice_next = I_CACHE;
                state_next = WAIT_FOR_RESP;
                transaction_counter_next = '0;
                transaction_next = LOAD;
                mem_read = 1'b1;
                mem_addr = i_addr;
            end else if ((d_read || d_write) && mem_ready) begin // pick dcache, dcache priority over icache
                cache_choice_next = D_CACHE;
                state_next = WAIT_FOR_RESP;
                transaction_counter_next = '0;
                if(d_read) begin // begin loading
                    transaction_next = LOAD;
                    mem_read = 1'b1;
                    mem_addr = d_addr;
                end else begin
                    transaction_counter_next = 3'h1; // begin writing: first burst
                    transaction_next = STORE;
                    mem_write = 1'b1;
                    mem_addr = d_addr;
                    mem_wdata = d_wdata_split[0];
                end
            end
        end else begin // going through counter states (state == WAIT_FOR_RESP)
            if (transaction == LOAD) begin // loads
                if (mem_rvalid) begin // received an 8B burst
                    if ((cache_choice == I_CACHE && mem_raddr == i_addr) || (cache_choice == D_CACHE && mem_raddr == d_addr))
                    begin
                        transaction_counter_next = transaction_counter + 3'h1;
                    end
                    // if (cache_choice == I_CACHE) begin
                    //     mem_addr = i_addr;
                    // end else begin
                    //     mem_addr = d_addr;
                    // end
                    if (transaction_counter == 3'h3) begin // received all 4 bursts
                        state_next = DECIDE;
                        transaction_counter_next = '0;
                        if (cache_choice == I_CACHE) begin
                            // if (mem_raddr == i_addr_reg && !mispredict) begin
                                // i_resp = 1'b1;
                            // end
                            if (mem_raddr == i_addr) begin
                                i_resp = 1'b1;
                            end
                        end else begin
                            if (mem_raddr == d_addr) begin
                                d_resp = 1'b1;
                            end
                        end 
                    end
                end
            end else begin // stores, can only be dcache
                if (mem_ready) begin
                    transaction_counter_next = transaction_counter + 3'h1;
                    mem_write = 1'b1;
                    mem_addr = d_addr;
                    mem_wdata = d_wdata_split[transaction_counter];
                    if (transaction_counter == 3'h3) begin
                        state_next = DECIDE;
                        d_resp = 1'b1;
                        transaction_counter_next = '0;
                    end
                end
            end
        end
    end

    // rdata back to cache
    always_comb begin
        i_rdata = {{mem_rdata}, {mem_read_buffer[2]}, {mem_read_buffer[1]}, {mem_read_buffer[0]}};
        d_rdata = {{mem_rdata}, {mem_read_buffer[2]}, {mem_read_buffer[1]}, {mem_read_buffer[0]}};
    end


endmodule: cacheline_adaptor
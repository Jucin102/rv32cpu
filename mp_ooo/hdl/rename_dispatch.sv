module rename_dispatch
import rv32i_types ::*; 
(
    input clk, rst,

    // I/O for instruction queue
    input logic [INSTR_FETCH_NUM * ($bits(pc_instr_t)) - 1 : 0] instr_bundle,
    input logic instr_queue_empty,

    output logic instr_queue_pop,
    
    // NOTE: should we move reservation stations into dispatch? Gets rid of these signals below, so we don't have to pass these big bundles as I/O

    // I/O for reservation stations
    input logic [NUM_RES_STATIONS - 1 : 0] res_stations_mask_in, // bit mask of stations being used (1 is being used)

    output logic [NUM_RES_STATIONS - 1 : 0] res_stations_mask_out,
    output rs_entry_t res_station_entry [NUM_RES_STATIONS],

    // I/O for ROB
    input logic [NUM_ROB_ENTRIES_BITS - 1 : 0] rob_number_dispatch, // next free rob number
    input logic [NUM_ROB_ENTRIES_BITS : 0] num_free_robs,
    input logic mispredict, // branch enable (when we need to jump/branch)
    
    output logic [SS_FACTOR_BITS : 0] rob_push, // number of rob entries we're pushing
    output rob_entry_t rob_entry[SS_FACTOR],

    // I/O for RAT
    input phys_reg ps1[SS_FACTOR],
    input phys_reg ps2[SS_FACTOR],
    
    // output logic [SS_FACTOR_BITS : 0] regf_we_rat, // number of RAT entries we're changing
    output arch_reg rd_dispatch[SS_FACTOR],
    output phys_reg pd_dispatch[SS_FACTOR],
    output arch_reg rs1[SS_FACTOR],
    output arch_reg rs2[SS_FACTOR],

    // I/O for free list
    input logic [NUM_FREE_LIST_BITS : 0] num_free_regs,
    input phys_reg free_reg [SS_FACTOR],

    output logic [SS_FACTOR_BITS : 0] free_list_pop, // number of free regs we're popping

    // I/O for regfile
    output phys_reg reg_invalidate_idx[SS_FACTOR],
    output logic [SS_FACTOR - 1 : 0] reg_invalidate_mask,

    // I/O for branch queue
    input logic [NUM_BRQ_ENTRIES_BITS : 0] num_free_brq_entries,

    output brq_entry_t brq_entry [SS_FACTOR],
    output logic [SS_FACTOR_BITS : 0] brq_push,

    // I/O for store queue
    input logic [NUM_LSQ_ENTRIES_BITS : 0] store_queue_free,
    
    output lsq_entry_t sq_entry [SS_FACTOR],
    output logic [SS_FACTOR_BITS : 0] sq_push,

    // I/O for load rs stations
    input logic [SS_FACTOR_BITS : 0] load_rs_push_limit,

    output load_rs_entry_t load_entry [SS_FACTOR],
    output logic [SS_FACTOR_BITS : 0] load_push
);

    pc_instr_t instr_bundle_struct [INSTR_FETCH_NUM]; // stores last read of instr queue, keeps until all are dispatched
    // pc_instr_t instr_bundle_reg [SS_FACTOR]; // stores last read of instr queue, keeps until all are dispatched
    logic [INSTR_FETCH_NUM - 1 : 0] instr_bundle_sent, instr_bundle_sent_next, instr_bundle_valids; // bit mask of instructions not dispatched yet
    // logic [NUM_RES_STATIONS - 1 : 0] internal_res_mask; // internal mask used for finding multiple reservation stations
    logic [MAX_BIT_COUNT : 0] min_robs_regs; // min between number of free robs and free physical regs
    logic [MAX_BIT_COUNT : 0] num_free_res_stations; // free res stations up to ss_factor
    logic [MAX_BIT_COUNT : 0] instrs_left_in_bundle; // # of instructions left in the bundle to dispatch
    logic [MAX_BIT_COUNT : 0] min_res_bundle; // min between free res stations and instrs left in bundle
    logic [MAX_BIT_COUNT : 0] min_above_4; // min of above 4
    logic [MAX_BIT_COUNT : 0] min_above_5; // min of above 5
    logic [MAX_BIT_COUNT : 0] dispatch_count; // number of instructions to dispatch = min of the above
    // logic [MAX_BIT_COUNT : 0] rd_non_zero_count; // number of instructions using rd that's not r0
    logic [MAX_BIT_COUNT : 0] dispatched; // number of instructions dispatched in current cycle
    logic [MAX_BIT_COUNT : 0] dispatched_map_pd; // number of instructions dispatched that used a new free register
    logic [NUM_ROB_ENTRIES_BITS - 1 : 0 ] curr_rob_number; // current ROB number, starts at rob_number_dispatch, and increments until we dispatched our instrs
    logic [RES_STATION_BITS : 0] stations_to_use [SS_FACTOR];

    logic [MAX_BIT_COUNT : 0] used_res_stations;

    // logic sent_next_anded;
    // assign sent_next_anded = !instr_queue_empty && &instr_bundle_sent_next;

    always_ff @(posedge clk) begin
        if (rst || mispredict) begin
            instr_bundle_sent <= '0;
        end else begin
            if(!instr_queue_empty && instr_bundle_sent_next == instr_bundle_valids) begin
                instr_bundle_sent <= '0;
            end else begin
                instr_bundle_sent <= instr_bundle_sent_next;
            end
        end
    end

    // figure out how many instructions we're going to dispatch
    always_comb begin
        // convert instruction bundle to pc_instr_t
        for(int unsigned i = 0; i < INSTR_FETCH_NUM; i++) begin
            // instr_bundle_struct[i] = instr_bundle[i * (INSTR_WIDTH * 2 + 1) +: 65];
            instr_bundle_struct[i] = instr_bundle[i*PC_INSTR_T_BITS +: PC_INSTR_T_BITS]; // changed to accomodate the fact that br_taken_pred is not an element of pc_instr_t
            instr_bundle_valids[i] = instr_bundle_struct[i].valid;
        end
        
        // min between number of free regs and free robs
        min_robs_regs = ((MAX_BIT_COUNT + 1)'(num_free_regs) < (MAX_BIT_COUNT + 1)'(num_free_robs)) ? (MAX_BIT_COUNT + 1)'(num_free_regs) : (MAX_BIT_COUNT + 1)'(num_free_robs);
        // fill SS_FACTOR sized list of reservation station indexes, then take min between min_robs_regs and SS_FACTOR
        for(int i = 0; i < SS_FACTOR; i++) begin
            stations_to_use[i] = '0;
        end
        num_free_res_stations = '0;
        instrs_left_in_bundle = '0;
        min_above_4 = '0;
        min_above_5 = '0;
        dispatch_count = '0;
        // rd_non_zero_count = '0;

        for(int unsigned i = 0; i < NUM_RES_STATIONS; i++) begin
            if(res_stations_mask_in[i] == 0) begin
                stations_to_use[num_free_res_stations] = (RES_STATION_BITS + 1)'(i); // might not work due to bit width
                num_free_res_stations += (MAX_BIT_COUNT + 1)'(1);
            end
        end
        // for(int unsigned i = 0; i < SS_FACTOR; i++) begin
        for(int unsigned i = 0; i < INSTR_FETCH_NUM; i++) begin
            if(instr_bundle_struct[i].valid && !instr_bundle_sent[i]) begin
                instrs_left_in_bundle += (MAX_BIT_COUNT + 1)'(1);
                // if(instr_bundle_struct[i].instruction.i_type.rd != '0 && !(instr_bundle_struct[i].instruction.i_type.opcode inside {op_store, op_br})) begin
                //     rd_non_zero_count += (MAX_BIT_COUNT + 1)'(1);
                // end
            end
        end
    
        instrs_left_in_bundle = (instrs_left_in_bundle < (MAX_BIT_COUNT + unsigned'(1))'(SS_FACTOR + unsigned'(1))) ? instrs_left_in_bundle : (MAX_BIT_COUNT + unsigned'(1))'(SS_FACTOR);

        min_res_bundle = (num_free_res_stations < instrs_left_in_bundle) ? num_free_res_stations : instrs_left_in_bundle;
        min_above_4 = (min_robs_regs < min_res_bundle) ? min_robs_regs : min_res_bundle;
        min_above_5 = ((MAX_BIT_COUNT + 1)'(min_above_4) < (MAX_BIT_COUNT + 1)'(store_queue_free)) ? (MAX_BIT_COUNT + 1)'(min_above_4) : (MAX_BIT_COUNT + 1)'(store_queue_free);
        if(!rst && !mispredict) begin
            dispatch_count = ((MAX_BIT_COUNT + 1)'(min_above_5) < (MAX_BIT_COUNT + 1)'(num_free_brq_entries)) ? (MAX_BIT_COUNT + 1)'(min_above_5) : (MAX_BIT_COUNT + 1)'(num_free_brq_entries);
        end


        // // request free registers from free list
        // if (!instr_queue_empty) begin
        //     free_list_pop = (SS_FACTOR_BITS + 1)'((rd_non_zero_count < dispatch_count) ? rd_non_zero_count : dispatch_count); // probs give error cuz bit width
        // end
        
    end

    always_comb begin
        logic store_dispatched;

        store_dispatched = 1'b0;

        instr_queue_pop = 1'b0;
        
        // bundle logic
        instr_bundle_sent_next = instr_bundle_sent;
        dispatched = '0;
        dispatched_map_pd = '0;

        // rob logic
        curr_rob_number = rob_number_dispatch;
        rob_push = '0;

        for(int unsigned i = 0; i < SS_FACTOR; i++) begin
            rob_entry[i] = '0;
            brq_entry[i] = '0;
            sq_entry[i] = '0;
            load_entry[i] = '0;

            rd_dispatch[i] = '0;
            pd_dispatch[i] = '0;
            rs1[i] = '0;
            rs2[i] = '0;

            reg_invalidate_idx[i] = '0;
        end

        // brq logic
        brq_push = '0;

        sq_push = '0;
        load_push = '0;

        // res station logic
        res_stations_mask_out = '0;
        for(int unsigned i = 0; i < NUM_RES_STATIONS; i++) begin
            res_station_entry[i] = '0;
        end

        // rat logic
        // regf_we_rat = '0;
        // rd_dispatch = '0;
        // pd_dispatch = '0;
        // rs1 = '0;
        // rs2 = '0;

        // regfile logic
        // reg_invalidate_idx = '0;
        reg_invalidate_mask = '0;

        free_list_pop = '0;


        // ADD BREAK WHEN WE SENT MORE THAN DISPATCH_COUNT
        // for(int unsigned i = 0; i < SS_FACTOR; i++) begin
        for(int unsigned i = 0; i < INSTR_FETCH_NUM; i++) begin
            if(instr_bundle_struct[i].valid && !instr_queue_empty && !instr_bundle_sent[i] && dispatched < dispatch_count) begin
                // send current instruction
                instr_bundle_sent_next[i] = 1'b1;
                res_station_entry[stations_to_use[dispatched]].pc = instr_bundle_struct[i].pc;
                // index into free_reg using dispatched
                // decode and send reservation station values
                if (instr_bundle_struct[i].instruction.i_type.opcode inside {op_lui, op_auipc, op_jal}) begin
                    // map rd
                    if (instr_bundle_struct[i].instruction.i_type.rd != '0) begin

                        free_list_pop += (SS_FACTOR_BITS + unsigned'(1))'(unsigned'(1));

                        res_station_entry[stations_to_use[dispatched]].pd_s = free_reg[dispatched_map_pd];
                        rd_dispatch[dispatched] = instr_bundle_struct[i].instruction.u_type.rd;
                        pd_dispatch[dispatched] = free_reg[dispatched_map_pd];
                        reg_invalidate_idx[dispatched_map_pd] = free_reg[dispatched_map_pd];
                        reg_invalidate_mask[dispatched_map_pd] = 1'b1;
                        res_station_entry[stations_to_use[dispatched]].rvfi_data.rd_s = instr_bundle_struct[i].instruction.i_type.rd;
                        rob_entry[dispatched].phys_reg_d = free_reg[dispatched_map_pd];

                        // regf_we_rat += (SS_FACTOR_BITS + 1)'(1);
                        dispatched_map_pd += (MAX_BIT_COUNT + unsigned'(1))'(unsigned'(1));
                    end

                    // rob entry destination reg mapping
                    rob_entry[dispatched].arch_reg_d = instr_bundle_struct[i].instruction.u_type.rd;

                end else if (instr_bundle_struct[i].instruction.i_type.opcode inside {op_jalr, op_imm}) begin
                    // map rs1
                    rs1[dispatched] = instr_bundle_struct[i].instruction.i_type.rs1;
                    res_station_entry[stations_to_use[dispatched]].ps1_s = ps1[dispatched];
                    res_station_entry[stations_to_use[dispatched]].rvfi_data.rs1_s = instr_bundle_struct[i].instruction.i_type.rs1;

                    // map rd
                    if (instr_bundle_struct[i].instruction.i_type.rd != '0) begin

                        free_list_pop += (SS_FACTOR_BITS + unsigned'(1))'(unsigned'(1));

                        res_station_entry[stations_to_use[dispatched]].pd_s = free_reg[dispatched_map_pd];
                        rd_dispatch[dispatched] = instr_bundle_struct[i].instruction.u_type.rd;
                        pd_dispatch[dispatched] = free_reg[dispatched_map_pd];
                        reg_invalidate_idx[dispatched_map_pd] = free_reg[dispatched_map_pd];
                        reg_invalidate_mask[dispatched_map_pd] = 1'b1;
                        res_station_entry[stations_to_use[dispatched]].rvfi_data.rd_s = instr_bundle_struct[i].instruction.i_type.rd;
                        rob_entry[dispatched].phys_reg_d = free_reg[dispatched_map_pd];

                        // regf_we_rat += (SS_FACTOR_BITS + 1)'(1);
                        dispatched_map_pd += (MAX_BIT_COUNT + unsigned'(1))'(unsigned'(1));
                    end
                    // rob entry destination reg mapping
                    rob_entry[dispatched].arch_reg_d = instr_bundle_struct[i].instruction.u_type.rd;

                end else if (instr_bundle_struct[i].instruction.i_type.opcode inside {op_load}) begin
                    if (store_dispatched != 1'b1 && load_push < load_rs_push_limit)
                    begin
                        rs1[dispatched] = instr_bundle_struct[i].instruction.i_type.rs1;
                        // lsq_entry[lsq_push].rvfi_data.rs1_s = instr_bundle_struct[i].instruction.i_type.rs1;
                        load_entry[load_push].rvfi_data.rs1_s = instr_bundle_struct[i].instruction.i_type.rs1;

                        if (instr_bundle_struct[i].instruction.i_type.rd != '0) begin

                            free_list_pop += (SS_FACTOR_BITS + unsigned'(1))'(unsigned'(1));

                            rd_dispatch[dispatched] = instr_bundle_struct[i].instruction.u_type.rd;
                            pd_dispatch[dispatched] = free_reg[dispatched_map_pd];
                            reg_invalidate_idx[dispatched_map_pd] = free_reg[dispatched_map_pd];
                            reg_invalidate_mask[dispatched_map_pd] = 1'b1;
                            rob_entry[dispatched].phys_reg_d = free_reg[dispatched_map_pd];
                            // load case
                            load_entry[load_push].pd_s = free_reg[dispatched_map_pd];
                            load_entry[load_push].rvfi_data.rd_s = instr_bundle_struct[i].instruction.i_type.rd;

                            // regf_we_rat += (SS_FACTOR_BITS + 1)'(1);
                            dispatched_map_pd += (MAX_BIT_COUNT + unsigned'(1))'(unsigned'(1));
                        end

                        // load case
                        load_entry[load_push].ps1_s = ps1[dispatched];
                        load_entry[load_push].rob_num = curr_rob_number;
                        load_entry[load_push].instr = instr_bundle_struct[i].instruction;
                        rob_entry[dispatched].arch_reg_d = instr_bundle_struct[i].instruction.u_type.rd;
                    end
                    else
                    begin
                        instr_bundle_sent_next[i] = 1'b0; // undo the signal that we sent
                        break; // stop dispatching after we fail to dispatch a load
                    end

                end else if (instr_bundle_struct[i].instruction.i_type.opcode inside {op_br}) begin
                    // map rs1
                    rs1[dispatched] = instr_bundle_struct[i].instruction.b_type.rs1;
                    res_station_entry[stations_to_use[dispatched]].ps1_s = ps1[dispatched];
                    res_station_entry[stations_to_use[dispatched]].rvfi_data.rs1_s = instr_bundle_struct[i].instruction.b_type.rs1;

                    // map rs2
                    rs2[dispatched] = instr_bundle_struct[i].instruction.b_type.rs2;
                    res_station_entry[stations_to_use[dispatched]].ps2_s = ps2[dispatched];
                    res_station_entry[stations_to_use[dispatched]].rvfi_data.rs2_s = instr_bundle_struct[i].instruction.b_type.rs2;

                end else if (instr_bundle_struct[i].instruction.i_type.opcode inside {op_store}) begin
                    // map rs1
                    rs1[dispatched] = instr_bundle_struct[i].instruction.b_type.rs1;
                    sq_entry[sq_push].ps1_s = ps1[dispatched];
                    sq_entry[sq_push].rvfi_data.rs1_s = instr_bundle_struct[i].instruction.b_type.rs1;

                    // map rs2
                    rs2[dispatched] = instr_bundle_struct[i].instruction.b_type.rs2;
                    sq_entry[sq_push].ps2_s = ps2[dispatched];
                    sq_entry[sq_push].rvfi_data.rs2_s = instr_bundle_struct[i].instruction.b_type.rs2;

                    // store case
                    sq_entry[sq_push].rob_num = curr_rob_number;
                    sq_entry[sq_push].store_load_inst = instr_bundle_struct[i].instruction;

                    store_dispatched = 1'b1;

                end else begin
                    // map rs1
                    rs1[dispatched] = instr_bundle_struct[i].instruction.r_type.rs1;
                    res_station_entry[stations_to_use[dispatched]].ps1_s = ps1[dispatched];
                    res_station_entry[stations_to_use[dispatched]].rvfi_data.rs1_s = instr_bundle_struct[i].instruction.r_type.rs1;

                    // map rs2 
                    rs2[dispatched] = instr_bundle_struct[i].instruction.r_type.rs2;
                    res_station_entry[stations_to_use[dispatched]].ps2_s = ps2[dispatched];
                    res_station_entry[stations_to_use[dispatched]].rvfi_data.rs2_s = instr_bundle_struct[i].instruction.r_type.rs2;

                    // map rd
                    if (instr_bundle_struct[i].instruction.i_type.rd != '0) begin

                        free_list_pop += (SS_FACTOR_BITS + unsigned'(1))'(unsigned'(1));
                        
                        res_station_entry[stations_to_use[dispatched]].pd_s = free_reg[dispatched_map_pd];
                        rd_dispatch[dispatched] = instr_bundle_struct[i].instruction.u_type.rd;
                        pd_dispatch[dispatched] = free_reg[dispatched_map_pd];
                        reg_invalidate_idx[dispatched_map_pd] = free_reg[dispatched_map_pd];
                        reg_invalidate_mask[dispatched_map_pd] = 1'b1;
                        res_station_entry[stations_to_use[dispatched]].rvfi_data.rd_s = instr_bundle_struct[i].instruction.i_type.rd;
                        rob_entry[dispatched].phys_reg_d = free_reg[dispatched_map_pd];

                        // regf_we_rat += (SS_FACTOR_BITS + 1)'(1);
                        dispatched_map_pd += (MAX_BIT_COUNT + unsigned'(1))'(unsigned'(1));
                    end

                    // rob entry destination reg mapping
                    rob_entry[dispatched].arch_reg_d = instr_bundle_struct[i].instruction.u_type.rd;
                end

                // check for branch/jal/jalr for branch queue
                if (instr_bundle_struct[i].instruction.i_type.opcode inside {op_jal, op_jalr, op_br}) begin
                    brq_entry[brq_push].rob_idx = curr_rob_number;
                    brq_push += (SS_FACTOR_BITS + unsigned'(1))'(unsigned'(1));
                end

                // reservation station mask: index into stations_to_use using dispatched, and use that to index into res_stations_mask_out
                if (!(instr_bundle_struct[i].instruction.i_type.opcode inside {op_load, op_store})) begin
                    res_stations_mask_out[stations_to_use[dispatched]] = 1'b1;
                end
                res_station_entry[stations_to_use[dispatched]].instr = instr_bundle_struct[i].instruction.word;
                res_station_entry[stations_to_use[dispatched]].rob_num = curr_rob_number;

                // sending whether branch was predicted to be taken 
                res_station_entry[stations_to_use[dispatched]].br_taken_pred = instr_bundle_struct[i].br_taken_pred; // ok to always set this b/c it will be overwritten by future instr that actually use this res_station_entry
                
                // rob entry
                rob_push += (SS_FACTOR_BITS + unsigned'(1))'(unsigned'(1));
                rob_entry[dispatched].valid = 1'b0;

                // rvfi data
                res_station_entry[stations_to_use[dispatched]].rvfi_data.inst = instr_bundle_struct[i].instruction.word;
                res_station_entry[stations_to_use[dispatched]].rvfi_data.pc_rdata = instr_bundle_struct[i].pc;
                res_station_entry[stations_to_use[dispatched]].rvfi_data.pc_wdata = instr_bundle_struct[i].pc + 4;

                if (instr_bundle_struct[i].instruction.i_type.opcode == op_store)
                begin
                    sq_entry[sq_push].rvfi_data.inst = instr_bundle_struct[i].instruction.word;
                    sq_entry[sq_push].rvfi_data.pc_rdata = instr_bundle_struct[i].pc;
                    sq_entry[sq_push].rvfi_data.pc_wdata = instr_bundle_struct[i].pc + 4;
                end
                if (instr_bundle_struct[i].instruction.i_type.opcode == op_load)
                begin
                    load_entry[load_push].rvfi_data.inst = instr_bundle_struct[i].instruction.word;
                    load_entry[load_push].rvfi_data.pc_rdata = instr_bundle_struct[i].pc;
                    load_entry[load_push].rvfi_data.pc_wdata = instr_bundle_struct[i].pc + 4;
                end

                if (instr_bundle_struct[i].instruction.i_type.opcode == op_store) begin
                    rob_entry[dispatched].rvfi_data = sq_entry[sq_push].rvfi_data;
                end 
                else if (instr_bundle_struct[i].instruction.i_type.opcode == op_load)
                begin
                    rob_entry[dispatched].rvfi_data = load_entry[load_push].rvfi_data;
                end
                else begin
                    rob_entry[dispatched].rvfi_data = res_station_entry[stations_to_use[dispatched]].rvfi_data;
                end

                if(instr_bundle_struct[i].instruction.i_type.opcode == op_store) begin
                    sq_push += (SS_FACTOR_BITS + unsigned'(1))'(unsigned'(1));
                end
                if (instr_bundle_struct[i].instruction.i_type.opcode == op_load)
                begin
                    load_push += (SS_FACTOR_BITS + unsigned'(1))'(unsigned'(1));
                end

                curr_rob_number += (NUM_ROB_ENTRIES_BITS)'(unsigned'(1));
                dispatched += (MAX_BIT_COUNT + unsigned'(1))'(unsigned'(1));
            end
        end

        if(!instr_queue_empty && instr_bundle_sent_next == instr_bundle_valids) begin
            // pop from instr queue, load into instr_bundle
            instr_queue_pop = 1'b1;
        end
    end

endmodule: rename_dispatch

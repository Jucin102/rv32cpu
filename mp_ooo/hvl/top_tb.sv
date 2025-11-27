import "DPI-C" function string getenv(input string env_name);
import rv32i_types::*;

module top_tb;

    timeunit 1ps;
    timeprecision 1ps;

    int clock_half_period_ps = getenv("CLOCK_PERIOD_PS").atoi() / 2;

    bit clk;
    always #(clock_half_period_ps) clk = ~clk;

    bit rst;

    int timeout = 1000000000; // in cycles, change according to your needs

    // Explicit dual port connections when caches are not integrated into design yet (Before CP3)
    // mem_itf mem_itf_i(.*);
    // mem_itf mem_itf_d(.*);
    // magic_dual_port mem(.itf_i(mem_itf_i), .itf_d(mem_itf_d));

    // Single memory port connection when caches are integrated into design (CP3 and after)
    banked_mem_itf bmem_itf(.*);
    banked_memory banked_memory(.itf(bmem_itf));

    mon_itf mon_itf(.*);
    monitor monitor(.itf(mon_itf));

    logic cp1_pop, cp1_push;

    

    cpu dut(
        .clk            (clk),
        .rst            (rst),

        // Explicit dual port connections when caches are not integrated into design yet (Before CP3)
        // .imem_addr      (mem_itf_i.addr),
        // .imem_rmask     (mem_itf_i.rmask),
        // .imem_rdata     (mem_itf_i.rdata),
        // .imem_resp      (mem_itf_i.resp),

        // // .dmem_addr      (mem_itf_d.addr),
        // // .dmem_rmask     (mem_itf_d.rmask),
        // // .dmem_wmask     (mem_itf_d.wmask),
        // // .dmem_rdata     (mem_itf_d.rdata),
        // // .dmem_wdata     (mem_itf_d.wdata),
        // // .dmem_resp      (mem_itf_d.resp)

        // .instr_queue_pop (cp1_pop)
        // .cp1_instr_queue_push (cp1_push)

        // Single memory port connection when caches are integrated into design (CP3 and after)
        .bmem_addr(bmem_itf.addr),
        .bmem_read(bmem_itf.read),
        .bmem_write(bmem_itf.write),
        .bmem_wdata(bmem_itf.wdata),
        .bmem_ready(bmem_itf.ready),
        .bmem_raddr(bmem_itf.raddr),
        .bmem_rdata(bmem_itf.rdata),
        .bmem_rvalid(bmem_itf.rvalid)
    );

    `include "../../hvl/rvfi_reference.svh"

    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, "+all");
        rst = 1'b1;
        cp1_pop = 1'b0;
        repeat (2) @(posedge clk);
        rst <= 1'b0;

        // test push not pop, push pop with 1 elem, push pop while full
        repeat (2) @(posedge clk);
        cp1_pop = 1'b1;
        repeat (8) @(posedge clk);
        cp1_pop = 1'b0;
        repeat (8) @(posedge clk);
        cp1_pop = 1'b1;
        
        // test pop while empty
        // cp1_pop = 1'b1;
        // cp1_push = 1'b0;
    end

    longint clock_counter = 0;
    longint instr_queue_empty_counter = 0;
    longint free_list_free_entries_counter = 0;
    longint rob_free_entries_counter = 0;
    longint rob_empty_counter = 0;
    longint cdb_occupancy_counter = 0;
    longint occupied_res_stations_counter = 0;
    longint sq_free_entries_counter = 0;
    longint sq_empty_counter = 0;
    longint brq_free_entries_counter = 0;
    longint brq_empty_counter = 0;
    longint alu_busy_entries_counter = 0;
    longint mult_busy_entries_counter = 0;

    longint cdb_occupancy_temp = 0;
    longint occupied_res_station_temp = 0;

    longint num_mispredicts = 0;
    longint num_control_instr = 0; 
    longint num_dispatch = 0;

    longint free_load_rs_counter = 0;
    longint load_rs_full_cycles = 0;

    always @(posedge clk) begin
        for (int unsigned i=0; i < 8; ++i) begin
            if (mon_itf.halt[i]) begin
                $finish;
            end
        end
        if (timeout == 0) begin
            $error("TB Error: Timed out");
            $finish;
        end
        if (mon_itf.error != 0) begin
            repeat (5) @(posedge clk);
            $finish;
        end
        // if (mem_itf_i.error != 0) begin
        //     repeat (5) @(posedge clk);
        //     $finish;
        // end
        // if (mem_itf_d.error != 0) begin
        //     repeat (5) @(posedge clk);
        //     $finish;
        // end
        if (bmem_itf.error != 0) begin
            repeat (5) @(posedge clk);
            $finish;
        end
        timeout <= timeout - 1;

        clock_counter <= clock_counter + 1;
        // instruction queue empty counter:
        instr_queue_empty_counter <= instr_queue_empty_counter + dut.instr_queue_empty;
        
        // free_list_free_entries_counter:
        free_list_free_entries_counter <= free_list_free_entries_counter + dut.num_free_regs_free_list;
        // rob_free_entries_counter:
        rob_free_entries_counter <= rob_free_entries_counter + dut.num_free_regs_rob;
        rob_empty_counter <= rob_empty_counter + (dut.num_free_regs_rob != 0);
        

        // cdb_occupancy_counter
        cdb_occupancy_counter <= cdb_occupancy_temp;

        // sq_free_entries_counter
        sq_free_entries_counter <= sq_free_entries_counter + dut.lsq_free;
        sq_empty_counter <= sq_empty_counter + (dut.lsq_free != 0);

        // brq_free_entries_counter
        brq_free_entries_counter <= brq_free_entries_counter + dut.num_free_brq_entries;
        brq_empty_counter <= brq_empty_counter + (dut.num_free_brq_entries != 0);
        
        occupied_res_stations_counter <= occupied_res_stations_counter +  $countones(dut.dispatch_rs_busy);

        alu_busy_entries_counter <= alu_busy_entries_counter + $countones(dut.issue_alu_cmp_fu_busy);
        mult_busy_entries_counter <= mult_busy_entries_counter + $countones(dut.issue_mult_fu_busy);

        num_mispredicts <= num_mispredicts + dut.mispredict;
        num_control_instr <= num_control_instr + dut.branch_queue.branch_cnt; 

        num_dispatch <= num_dispatch + dut.rename_dispatch_stage.dispatched;
        free_load_rs_counter <= free_load_rs_counter + dut.load_rs_i.num_not_busy;
        load_rs_full_cycles <= load_rs_full_cycles + (dut.load_rs_push_limit == 0);

        if(clock_counter % 10000 == 0) begin
            $display("cycles, %d", clock_counter);
            $display("instruction queue empty: %f", real'(instr_queue_empty_counter) / real'(clock_counter));
            $display("free list free entries: %f", real'(free_list_free_entries_counter) / real'(clock_counter));
            $display("rob free entries: %f", real'(rob_free_entries_counter) / real'(clock_counter));
            $display("rob empty: %f", real'(rob_empty_counter) / real'(clock_counter));
            $display("cdb occupancy: %f", real'(cdb_occupancy_counter) / real'(clock_counter));
            $display("sq free entries: %f", real'(sq_free_entries_counter) / real'(clock_counter));
            $display("sq empty: %f", real'(sq_empty_counter) / real'(clock_counter));

            $display("mult_busy_avg: %f", real'(mult_busy_entries_counter) / real'(clock_counter));
            $display("alu_busy_avg: %f", real'(alu_busy_entries_counter) / real'(clock_counter));
            $display("occupied res stations avg: %f", real'(occupied_res_stations_counter) / real'(clock_counter));
            $display("brq free entries avg: %f", real'(brq_free_entries_counter) / real'(clock_counter));
            $display("brq free empty prop: %f", real'(brq_empty_counter) / real'(clock_counter));
            $display("control instr mispredict rate: %f", real'(num_mispredicts) / real'(num_control_instr));
            $display("avg dispatch count: %f", real'(num_dispatch) / real'(clock_counter));
            $display("avg free load rs: %f", real'(free_load_rs_counter) / real'(clock_counter));
            $display("prop of cycles with full load rs: %f", real'(load_rs_full_cycles) / real'(clock_counter));
        end
    end
    
    always_comb
    begin
        cdb_occupancy_temp = 0;
        for (int i = 0; i < NUM_CDB; ++i)
        begin
            if (dut.cdb[i].valid)
            begin
                cdb_occupancy_temp = cdb_occupancy_temp + 1;
            end
        end
    end
endmodule

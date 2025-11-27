module cheese_cache 
import rv32i_types ::*;
#(
    parameter OUTPUT_BYTES = 4,
    parameter OFFSET_BITS = ($clog2(OUTPUT_BYTES) == 5) ? 0 : $clog2(OUTPUT_BYTES),
    parameter OUTPUT_MULTIPLY = (OUTPUT_BYTES == 5) ? 0 : OUTPUT_BYTES
)
(
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic   [3:0]   ufp_rmask,
    output  logic   [OUTPUT_BYTES * 8 - 1 : 0]  ufp_rdata,
    output  logic           ufp_resp,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp
);

    enum logic[1:0] {IDLE, COMPARE_TAG, ALLOCATE} state, next_state;
    logic [1:0] replace_way, replace_way_next;

    logic [3:0] hit_arr; // if any of the 4 bits is 1 it's a valid hit
    logic [31 : 0] ufp_addr_reg;
    
    logic [255:0] ufp_rdata_temp;

    // data_array wires: input means input to data_array
    // data_array_t data_in_signals[4];
    logic           csb_data[4]; // input: active low chip select
    logic           web_data[4]; // input: active low write enable
    logic   [3:0]   addr_data[4]; // input: address (which set)
    // logic   [31:0]  wmask_data[4]; // input: write mask (which byte(s))
    logic   [31:0]  wmask_data;
    // logic   [255:0] din_data[4]; // input: input data
    logic   [255:0] din_data;
    logic   [255:0] dout_data[4]; // output: output data

    // tag_array wires: input means input to tag_array
    // tag_array_t tag_in_signals[4];
    logic           csb_tag[4]; // input: active low chip select
    logic           web_tag[4]; // input: active low write enable
    logic   [3:0]   addr_tag[4]; // input: address (which set)
    // logic   [23:0]  din_tag[4]; // input: input data (bit 23 is dirty bit)
    logic   [23:0]  din_tag;
    logic   [23:0]  dout_tag[4]; // output: output data (bit 23 is dirty bit)

    // valid_array wires: input means input to valid_array
    // valid_array_t valid_in_signals[4];
    logic           csb_valid[4]; // input: active low chip select
    logic           web_valid[4]; // input: active low write enable
    logic   [3:0]   addr_valid[4]; // input: address (which set)
    logic           din_valid[4]; // input: input valid bit
    logic           dout_valid[4]; // output: output valid bit

    // plru_array wires: input means input to plru_array
    logic           csb_plru; // input: active low chip select
    logic           web_plru; // input: active low write enable
    logic   [3:0]   addr_plru; // input: address (which set)
    logic   [2:0]   din_plru; // input: input valid bit
    logic   [2:0]   dout_plru; // output: output valid bit

    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       (csb_data[i]),
            .web0       (web_data[i]),
            .addr0      (addr_data[i]),
            // .wmask0     (wmask_data[i]),
            .wmask0     (wmask_data),
            // .din0       (din_data[i]),
            .din0       (din_data),
            .dout0      (dout_data[i])
        );
        mp_cache_tag_array tag_array (
            .clk0       (clk),
            .csb0       (csb_tag[i]),
            .web0       (web_tag[i]),
            .addr0      (addr_tag[i]),
            // .din0       (din_tag[i]),
            .din0       (din_tag),
            .dout0      (dout_tag[i])
        );
        ff_array #(.WIDTH(1)) valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (csb_valid[i]),
            .web0       (web_valid[i]),
            .addr0      (addr_valid[i]),
            .din0       (din_valid[i]),
            .dout0      (dout_valid[i])
        );
    end endgenerate

    ff_array #(.WIDTH(3)) plru_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       (csb_plru),
        .web0       (web_plru),
        .addr0      (addr_plru),
        .din0       (din_plru),
        .dout0      (dout_plru)
    );

    // 23 bit tag, 4 bit index, 5 bit offset
    logic [22:0] tag, tag_prev;
    logic [3:0] index;
    logic [4:0] offset, offset_prev;

    always_ff @ (posedge clk) begin
        if(rst) begin
            state <= IDLE;
            replace_way <= 2'b00;
        end else begin
            state <= next_state;
            replace_way <= replace_way_next;
            ufp_addr_reg <= ufp_addr;
        end
    end

    // which 4-byte chunk we're looking for inside 32 bytes
    logic [255:0] shift_amt;

    always_comb begin
        // ufp and dfp signals that cache outputs
        ufp_resp = '0;
        ufp_rdata = '0;
        dfp_addr = '0;
        dfp_read = '0;
        dfp_write = '0;
        dfp_wdata = '0;

        // dissect input address:
        tag = ufp_addr[31:9];
        tag_prev = ufp_addr_reg[31 : 9];
        index = ufp_addr[8:5];
        offset = ufp_addr[4:0];
        offset_prev = ufp_addr_reg[4 : 0];

        next_state = IDLE;
        replace_way_next = replace_way;
        shift_amt = unsigned'((256)'(unsigned'(8) * OUTPUT_MULTIPLY * offset_prev[4 : OFFSET_BITS]));

        for(int i = 0; i < 4; i++) begin
            // data_array signals that cache outputs
            csb_data[i] = '1;
            web_data[i] = '1;
            addr_data[i] = '0;
            // wmask_data[i] = '0;
            // din_data[i] = '0;

            // tag_array signals that cache outputs
            csb_tag[i] = '1;
            web_tag[i] = '1;
            addr_tag[i] = '0;
            // din_tag[i] = '0;

            // valid_array signals that cache outputs
            csb_valid[i] = '1;
            web_valid[i] = '1;
            addr_valid[i] = '0;
            din_valid[i] = '0;

            hit_arr[i] = '0;
        end
        wmask_data = '0;
        din_data = '0;
        din_tag = '0;
        // plru_array signals that cache outputs
        csb_plru = '1;
        web_plru = '1;
        addr_plru = '0;
        din_plru = '0;

        ufp_rdata_temp = '0;

        unique case (state)
            IDLE: begin
                if(|ufp_rmask) begin
                    next_state = COMPARE_TAG;
                    for(int i = 0; i < 4; i++) begin
                        // begin reading from SRAMs (do this in idle since it takes 1 cycle to repond, not instant)
                        csb_tag[i] = 1'b0;
                        addr_tag[i] = index;

                        csb_data[i] = 1'b0;
                        addr_data[i] = index;
                        // begin reading from FFs (same reason as SRAM)
                        csb_valid[i] = 1'b0;
                        addr_valid[i] = index;
                    end
                    csb_plru = 1'b0;
                    addr_plru = index;
                end
            end

            COMPARE_TAG: begin
                // index into tag_array and check if we have hit
                for(int i = 0; i < 4; i++) begin // set all signals besides web,
                    csb_data[i] = 1'b0;
                    addr_data[i] = index;
                    
                    csb_tag[i] = 1'b0;
                    addr_tag[i] = index;

                    csb_valid[i] = 1'b0;
                    addr_valid[i] = index;
                    
                    hit_arr[i] = ((tag == dout_tag[i][22:0]) && dout_valid[i]);
                end
                din_tag = {{1'b0}, {tag}};
                
                csb_plru = 1'b0; // only 1 plru per set
                addr_plru = index;

                // check for tag match
                if (tag_prev == dout_tag[0][22:0] && dout_valid[0]) begin // match tag 0
                    if (|ufp_rmask) begin // read
                        // ufp_rdata = {{dout_data[0][start_bit -: 32]}}; // get the right 4-byte data using offset
                        ufp_rdata_temp = {dout_data[0] >> shift_amt};
                        // ufp_rdata = ufp_rdata_temp[31:0];
                        ufp_rdata = ufp_rdata_temp[OUTPUT_BYTES * 8 - 1 : 0];
                    end else begin // write
                        web_data[0] = 1'b0;
                        // dirty bit attached on tag
                        web_tag[0] = 1'b0;
                        // din_tag[0][23] = 1'b1;
                        din_tag[23] = 1'b1;
                    end
                    web_plru = 1'b0; // update plru
                    din_plru = {{1'b0}, {1'b0}, {dout_plru[0]}}; // {00x}

                    ufp_resp = 1'b1;
                    next_state = (|ufp_rmask) ? COMPARE_TAG : IDLE;
                    // next_state = IDLE;
                end else if (tag_prev == dout_tag[1][22:0] && dout_valid[1]) begin // match tag 1
                    if (|ufp_rmask) begin // read
                        // ufp_rdata = {{dout_data[1][start_bit -: 32]}}; // get the right 4-byte data using offset
                        ufp_rdata_temp = {dout_data[1] >> shift_amt};
                        // ufp_rdata = ufp_rdata_temp[31:0];
                        ufp_rdata = ufp_rdata_temp[OUTPUT_BYTES * 8 - 1 : 0];
                    end else begin // write
                        web_data[1] = 1'b0;
                        // dirty bit
                        web_tag[1] = 1'b0;
                        // din_tag[1][23] = 1'b1;
                        din_tag[23] = 1'b1;
                    end
                    web_plru = 1'b0; // update plru
                    din_plru = {{1'b0}, {1'b1}, {dout_plru[0]}}; // {01x}

                    ufp_resp = 1'b1;
                    next_state = (|ufp_rmask) ? COMPARE_TAG : IDLE;
                    // next_state = IDLE;
                end else if (tag_prev == dout_tag[2][22:0] && dout_valid[2]) begin // match tag 2
                    if (|ufp_rmask) begin // read
                        // ufp_rdata = {{dout_data[2][start_bit -: 32]}}; // get the right 4-byte data using offset
                        ufp_rdata_temp = {dout_data[2] >> shift_amt};
                        // ufp_rdata = ufp_rdata_temp[31:0];
                        ufp_rdata = ufp_rdata_temp[OUTPUT_BYTES * 8 - 1 : 0];
                    end else begin // write
                        web_data[2] = 1'b0;
                        // dirty bit
                        web_tag[2] = 1'b0;
                        // din_tag[2][23] = 1'b1;
                        din_tag[23] = 1'b1;
                    end
                    web_plru = 1'b0; // update plru
                    din_plru = {{1'b1}, {dout_plru[1]}, {1'b0}}; // {1x0}
                    
                    ufp_resp = 1'b1;
                    next_state = (|ufp_rmask) ? COMPARE_TAG : IDLE;
                    // next_state = IDLE;
                end else if (tag_prev == dout_tag[3][22:0] && dout_valid[3]) begin // match tag 3
                    if (|ufp_rmask) begin // read
                        // ufp_rdata = {{dout_data[3][start_bit -: 32]}}; // get the right 4-byte data using offset
                        ufp_rdata_temp = {dout_data[3] >> shift_amt};
                        // ufp_rdata = ufp_rdata_temp[31:0];
                        ufp_rdata = ufp_rdata_temp[OUTPUT_BYTES * 8 - 1 : 0];
                    end else begin // write
                        web_data[3] = 1'b0;
                        // dirty bit
                        web_tag[3] = 1'b0;
                        // din_tag[3][23] = 1'b1;
                        din_tag[23] = 1'b1;
                    end
                    web_plru = 1'b0; // update plru
                    din_plru = {{1'b1}, {dout_plru[1]}, {1'b1}}; // {1x1}

                    ufp_resp = 1'b1;
                    next_state = (|ufp_rmask) ? COMPARE_TAG : IDLE;
                    // next_state = IDLE;
                end else begin // no match, kick someone out using plru
                    // figure out which way we're kicking out, check dirty bit, transition to allocate/write_back
                    if (dout_plru[2] && dout_plru[1]) begin // kick out wa
                        next_state = ALLOCATE;
                        replace_way_next = 2'b00;
                    end else if (dout_plru[2] && !dout_plru[1]) begin // kick out wb
                        next_state = ALLOCATE;
                        replace_way_next = 2'b01;
                    end else if (!dout_plru[2] && dout_plru[0]) begin // kick out wc
                        next_state = ALLOCATE;
                        replace_way_next = 2'b10;
                    end else begin // kick out wd
                        next_state = ALLOCATE;
                        replace_way_next = 2'b11;
                    end
                end
            end

            ALLOCATE: begin
                // clean miss: read from ram into current way
                dfp_addr = {{ufp_addr[31:5]}, {5'b00000}}; // dfp address is 256-bit aligned
                dfp_read = 1'b1;
                next_state = ALLOCATE;
                if(dfp_resp) begin // got response, begin writing to data array
                    csb_data[replace_way] = 1'b0;
                    web_data[replace_way] = 1'b0;
                    addr_data[replace_way] = index;
                    // wmask_data[replace_way] = '1; // replace the entire 32Byte line
                    wmask_data = '1;
                    // din_data[replace_way] = dfp_rdata;
                    din_data = dfp_rdata;

                    csb_tag[replace_way] = 1'b0;
                    web_tag[replace_way] = 1'b0;
                    addr_tag[replace_way] = index;
                    // din_tag[replace_way] = {{1'b0}, {tag}};
                    din_tag = {{1'b0}, {tag}};

                    csb_valid[replace_way] = 1'b0;
                    web_valid[replace_way] = 1'b0;
                    addr_valid[replace_way] = index;
                    din_valid[replace_way] = 1'b1;
                    // return to IDLE gives us 1 extra cycle to write to array, returning to COMPARE on the 2nd cycle after this one
                    next_state = IDLE;
                end
            end
            default:;
        endcase
    end

endmodule

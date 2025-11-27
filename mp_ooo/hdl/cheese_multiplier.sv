module cheese_multiplier
#(
    parameter int OPERAND_WIDTH = 32
)
(
    input logic clk,
    input logic rst,
    // Start must be reset after the done flag is set before another multiplication can execute
    input logic start,

    // Use this input to select what type of multiplication you are performing
    // 0 = Multiply two unsigned numbers
    // 1 = Multiply two signed numbers
    // 2 = Multiply a signed number and unsigned number
    //      a = signed
    //      b = unsigned
    input logic [1:0] mul_type,

    input logic[OPERAND_WIDTH-1:0] a,
    input logic[OPERAND_WIDTH-1:0] b,
    output logic[2*OPERAND_WIDTH-1:0] p,
    output logic done
);

    // Constants for multiplication case readability
    `define UNSIGNED_UNSIGNED_MUL 2'b00
    `define SIGNED_SIGNED_MUL     2'b01
    `define SIGNED_UNSIGNED_MUL   2'b10

    logic [2 * OPERAND_WIDTH - 1 : 0] dummy_reg_1, dummy_reg_2, dummy_reg_3, accumulator, a_comb;
    logic [OPERAND_WIDTH - 1 : 0] b_comb, a_reg, b_reg;
    logic dummy_1_v, dummy_2_v, dummy_3_v, dummy_start_reg, neg_result;
    logic [1 : 0] mul_type_reg;

    always_ff @ (posedge clk) begin
        if (rst) begin
            dummy_reg_1 <= '0;
            dummy_reg_2 <= '0;
            dummy_reg_3 <= '0;

            dummy_1_v <= '0;
            dummy_2_v <= '0;
            dummy_3_v <= '0;

        end else begin
            if (start) begin
                a_reg <= a;
                b_reg <= b;
                mul_type_reg <= mul_type;
                dummy_start_reg <= start;
            end else begin
                dummy_start_reg <= '0;
            end

            dummy_reg_1 <= accumulator;
            dummy_reg_2 <= dummy_reg_1;
            dummy_reg_3 <= dummy_reg_2;

            dummy_1_v <= dummy_start_reg;
            dummy_2_v <= dummy_1_v;
            dummy_3_v <= dummy_2_v;
        end
    end

    always_comb begin
        done = '0;
        p = '0;
        accumulator = '0;
        a_comb = '0;
        b_comb = '0;
        neg_result = '0;

        if (dummy_3_v) begin
            done = '1;
            p = dummy_reg_3;
        end

        if (dummy_start_reg) begin
            unique case (mul_type)
                `UNSIGNED_UNSIGNED_MUL:
                begin
                    neg_result = '0;   // Not used in case of unsigned mul, but just cuz . . .
                    a_comb = {{OPERAND_WIDTH{1'b0}}, a_reg};
                    b_comb = b_reg;
                end
                `SIGNED_SIGNED_MUL:
                begin
                    // A -*+ or +*- results in a negative number unless the "positive" number is 0
                    neg_result = (a_reg[OPERAND_WIDTH-1] ^ b_reg[OPERAND_WIDTH-1]) && ((a_reg != '0) && (b_reg != '0));
                    // If operands negative, make positive
                    a_comb = (a_reg[OPERAND_WIDTH-1]) ? {OPERAND_WIDTH*{1'b0}, (~a_reg + 1'b1)} : a_reg;
                    b_comb = (b_reg[OPERAND_WIDTH-1]) ? {(~b_reg + 1'b1)} : b_reg;
                end
                `SIGNED_UNSIGNED_MUL:
                begin
                    neg_result = a_reg[OPERAND_WIDTH-1];
                    a_comb = (a_reg[OPERAND_WIDTH-1]) ? {OPERAND_WIDTH*{1'b0}, (~a_reg + 1'b1)} : a_reg;
                    b_comb = b_reg;
                end
                default:;
            endcase
            for(int unsigned i = 0; i < 32; i++) begin
                if (b_comb[0]) accumulator = accumulator + a_comb;
                a_comb = a_comb << 1;
                b_comb = b_comb >> 1;
            end
            unique case (mul_type) 
                `UNSIGNED_UNSIGNED_MUL: accumulator = accumulator[2*OPERAND_WIDTH-1:0];
                `SIGNED_SIGNED_MUL,
                `SIGNED_UNSIGNED_MUL: accumulator = neg_result ? (~accumulator[2*OPERAND_WIDTH-1-1:0])+1'b1 : accumulator;
                default: ;
            endcase
        end
    end


endmodule

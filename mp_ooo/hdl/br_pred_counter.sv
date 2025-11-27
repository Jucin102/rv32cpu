module br_pred_counter
import rv32i_types::*;
(
    input logic clk, rst,
    input logic inc, dec, // assumes that only one of inc or dec will be high at one time
    output logic pred
);
    enum logic [1:0] {STRONG_NO_TAKE, WEAK_NO_TAKE, WEAK_TAKE, STRONG_TAKE} state, state_next;

    // next state logic
    always_comb
    begin
        if (rst)
        begin
            state_next = WEAK_TAKE; // assuming that most branches are taken the first time they are encountered
        end
        unique case (state)
            STRONG_NO_TAKE:
            begin
                if (inc)
                begin
                    state_next = WEAK_NO_TAKE;
                end
                else if (dec)
                begin
                    state_next = STRONG_NO_TAKE;
                end
                else
                begin
                    state_next = state;
                end
            end
            WEAK_NO_TAKE:
            begin
                if (inc)
                begin
                    state_next = WEAK_TAKE;
                end
                else if (dec)
                begin
                    state_next = STRONG_NO_TAKE;
                end
                else
                begin
                    state_next = state;
                end
            end
            WEAK_TAKE:
            begin
                if (inc)
                begin
                    state_next = STRONG_TAKE;
                end
                else if (dec)
                begin
                    state_next = WEAK_NO_TAKE;
                end
                else
                begin
                    state_next = state;
                end
            end
            STRONG_TAKE:
            begin
                if (inc)
                begin
                    state_next = STRONG_TAKE;
                end
                else if (dec)
                begin
                    state_next = WEAK_TAKE;
                end
                else
                begin
                    state_next = state;
                end
            end
            default: ;
        endcase
    end

    always_ff @(posedge clk)
    begin
        state <= state_next;
    end

    // output logic
    always_comb
    begin
        unique case (state)
            WEAK_TAKE, STRONG_TAKE:
            begin
                pred = 1'b1;
            end
            WEAK_NO_TAKE, STRONG_NO_TAKE:
            begin
                pred = 1'b0;
            end
            default: ;
        endcase
    end

endmodule
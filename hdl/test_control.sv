/***********************************************************************************************************************
 * Copyright (c) 2024 Virgil Dobjanschi dobjanschivirgil@gmail.com
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
 * documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all copies or substantial portions of
 * the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
 * WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
 * OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
 * OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 **********************************************************************************************************************/

/***********************************************************************************************************************
 * This module implements the tests for FT2232:
 * Test TEST_RECEIVE (0): Receive data from FT2232.
 * Test TEST_SEND_RECEIVE (1): Receive data from FT2232 and loop it back.
 * Test TEST_SEND (2): Send data to FT2232.
 **********************************************************************************************************************/
`timescale 1ps/1ps
`default_nettype none

`include "test_definitions.svh"

module control (
    input logic reset_i,
    input logic clk_24576000_i,
    input logic clk_22579200_i,
    // Input FIFO access
    output logic rd_in_fifo_clk_o,
    output logic rd_in_fifo_en_o,
    input logic rd_in_fifo_empty_i,
    input logic [7:0] rd_in_fifo_data_i,
    // Output FIFO ports
    output logic wr_out_fifo_clk_o,
    output logic wr_out_fifo_en_o,
    output logic [7:0] wr_out_fifo_data_o,
    input logic wr_out_fifo_full_i,
    input logic wr_out_fifo_afull_i,
    // LEDs
    output logic led_ctrl_err_o);

    logic clk;
    assign clk = clk_24576000_i;

    assign rd_in_fifo_clk_o = clk;
    assign wr_out_fifo_clk_o = clk;

`ifndef DATA_PACKETS_COUNT
    `define DATA_PACKETS_COUNT 8'd1
`endif

`ifndef DATA_PACKET_PAYLOAD
    `define DATA_PACKET_PAYLOAD 6'd63
`endif

    // State machines
    localparam STATE_IDLE       = 2'b00;
    localparam STATE_RD         = 2'b01;
    localparam STATE_WR_BUFFER  = 2'b10;
    localparam STATE_WR         = 2'b11;
    logic [1:0] state_m, next_state_m;

    // Protocol state machine
    localparam STATE_FIFO_CMD       = 1'b0;
    localparam STATE_FIFO_PAYLOAD   = 1'b1;
    logic fifo_state_m;

    // Write state machines
    localparam STATE_WR_CMD         = 1'd0;
    localparam STATE_WR_PAYLOAD     = 1'd1;
    logic wr_state_m;

    logic [1:0] last_fifo_cmd;
    logic [5:0] rd_payload_bytes;
    logic [5:0] wr_data_index;
    logic [7:0] wr_data[0:3];

    logic [7:0] test_number;
    logic [7:0] expected_test_data;
    logic [7:0] wr_packets;
    logic [5:0] wr_payload_bytes;

    //==================================================================================================================
    // The command handler
    //==================================================================================================================
    task handle_cmd_task (input logic [1:0] fifo_cmd, input logic [5:0] payload_length);
        (* parallel_case, full_case *)
        case (fifo_cmd)
            `CMD_TEST_START: begin
                led_ctrl_err_o <= 1'b0;

                if (payload_length == 6'd1) begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_CMD] Rd IN: CMD_TEST_START. \033[0;0m");
`endif
                    // Reset the test data
                    expected_test_data <= 8'd0;
                end else begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_CMD] Rd IN: CMD_TEST_START payload bytes: %d (expected 1). \033[0;0m",
                                    payload_length);
`endif
                    wr_data_index <= 6'd0;
                    wr_data[0] <= {`CMD_TEST_STOPPED, 6'h1};
                    wr_data[1] <= `TEST_ERROR_INVALID_START_PAYLOAD;

                    test_fail_task;

                    rd_in_fifo_en_o <= 1'b0;
                end
            end

            `CMD_TEST_DATA: begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_CMD] Rd IN: CMD_TEST_DATA payload bytes: %d. \033[0;0m", payload_length);
`endif
            end

            `CMD_TEST_STOP: begin
                if (payload_length == 6'd0) begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_CMD] Rd IN: CMD_TEST_STOP. \033[0;0m");
`endif
                    test_ok_task;
                end else begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_CMD] Rd IN: CMD_TEST_STOP payload bytes: %d (expected 0). \033[0;0m",
                                    payload_length);
`endif
                    wr_data_index <= 6'd0;
                    wr_data[0] <= {`CMD_TEST_STOPPED, 6'h1};
                    wr_data[1] <= `TEST_ERROR_INVALID_STOP_PAYLOAD;

                    test_fail_task;
                end

                rd_in_fifo_en_o <= 1'b0;
            end

            default: begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_CMD] Rd IN: invalid command: %d. \033[0;0m", fifo_cmd);
`endif
                wr_data_index <= 6'd0;
                wr_data[0] <= {`CMD_TEST_STOPPED, 6'h1};
                wr_data[1] <= `TEST_ERROR_INVALID_CMD;

                test_fail_task;

                rd_in_fifo_en_o <= 1'b0;
            end
        endcase
    endtask

    //==================================================================================================================
    // The payload handler
    //==================================================================================================================
    task handle_payload_task (input logic [1:0] fifo_cmd, input logic [7:0] fifo_data);
        (* parallel_case, full_case *)
        case (fifo_cmd)
            `CMD_TEST_START: begin
                test_number <= fifo_data;
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_PAYLOAD for CMD_TEST_START] Rd IN: %d. \033[0;0m",
                                    fifo_data);
`endif
                case (fifo_data)
                    `TEST_RECEIVE, `TEST_RECEIVE_SEND: begin
                    end

                    `TEST_SEND: begin
                        wr_payload_bytes <= `DATA_PACKET_PAYLOAD;
                        wr_packets <= `DATA_PACKETS_COUNT;

                        rd_in_fifo_en_o <= 1'b0;

                        wr_state_m <= STATE_WR_CMD;
                        state_m <= STATE_WR;
                    end

                    default: begin
                        wr_data_index <= 6'd0;
                        wr_data[0] <= {`CMD_TEST_STOPPED, 6'd2};
                        wr_data[1] <= `TEST_ERROR_INVALID_TEST_NUM;
                        wr_data[2] <= fifo_data;

                        test_fail_task;

                        rd_in_fifo_en_o <= 1'b0;
                    end
                endcase
            end

            `CMD_TEST_DATA: begin
                if (fifo_data == expected_test_data) begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_PAYLOAD for CMD_TEST_DATA] Rd IN: %d. \033[0;0m",
                                    fifo_data);
`endif
                    // For the loop back test write back the byte that was just received.
                    if (test_number == `TEST_RECEIVE_SEND) begin
                        // Write back the byte received
                        wr_data_index <= 6'd0;
                        wr_data[0] <= {`CMD_TEST_DATA, 6'd1};
                        wr_data[1] <= fifo_data;

                        rd_in_fifo_en_o <= 1'b0;

                        state_m <= STATE_WR_BUFFER;
                        next_state_m <= STATE_RD;
                    end

                    expected_test_data <= expected_test_data + 8'd1;
                end else begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_PAYLOAD for CMD_TEST_DATA] Rd IN: bad payload: %d (expected %d). \033[0;0m",
                                fifo_data, expected_test_data);
`endif
                    wr_data_index <= 6'd0;
                    wr_data[0] <= {`CMD_TEST_STOPPED, 6'd3};
                    wr_data[1] <= `TEST_ERROR_INVALID_TEST_DATA;
                    // Actually data received
                    wr_data[2] <= fifo_data;
                    // Expected data
                    wr_data[3] <= expected_test_data;

                    test_fail_task;

                    rd_in_fifo_en_o <= 1'b0;
                end
            end

            `CMD_TEST_STOP: begin
                // Does not have a payload.
            end

            default: begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_PAYLOAD] Rd IN: invalid command: %d. \033[0;0m",
                                fifo_cmd);
`endif
                wr_data_index <= 6'd0;
                wr_data[0] <= {`CMD_TEST_STOPPED, 6'h1};
                wr_data[1] <= `TEST_ERROR_INVALID_LAST_CMD;

                test_fail_task;

                rd_in_fifo_en_o <= 1'b0;
            end
        endcase
    endtask

    //==================================================================================================================
    // The write data handler
    //==================================================================================================================
    task write_data_task;
        if (~wr_out_fifo_afull_i && ~wr_out_fifo_full_i) begin
            (* parallel_case, full_case *)
            case (wr_state_m)
                STATE_WR_CMD: begin
                    // The beginning of a packet
                    wr_out_fifo_en_o <= 1'b1;
                    wr_out_fifo_data_o <= {`CMD_TEST_DATA, `DATA_PACKET_PAYLOAD};
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t<--- [STATE_WR_CMD] Wr OUT: %d. \033[0;0m",
                                {`CMD_TEST_DATA, `DATA_PACKET_PAYLOAD});
`endif
                    wr_state_m <= STATE_WR_PAYLOAD;
                end

                STATE_WR_PAYLOAD: begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t<--- [STATE_WR_PAYLOAD] Wr OUT: %d. \033[0;0m",
                                    expected_test_data);
`endif
                    // Send data from the packet
                    wr_out_fifo_en_o <= 1'b1;
                    wr_out_fifo_data_o <= expected_test_data;

                    expected_test_data <= expected_test_data + 8'd1;

                    wr_payload_bytes <= wr_payload_bytes - 8'd1;
                    if (wr_payload_bytes == 8'd1) begin
                        wr_packets <= wr_packets - 8'd1;
                        if (wr_packets == 8'd1) begin
                            test_ok_task;
                        end else begin
`ifdef D_CTRL_FINE
                            $display ($time, "\033[0;36m CTRL:\t[STATE_WR_PAYLOAD] Packet sent. \033[0;0m");
`endif
                            wr_payload_bytes <= `DATA_PACKET_PAYLOAD;
                            wr_state_m <= STATE_WR_CMD;
                        end
                    end
                end
            endcase
        end else begin
            wr_out_fifo_en_o <= 1'b0;
        end
  endtask

    //==================================================================================================================
    // The FIFO reader
    //==================================================================================================================
    task read_data_task (input logic [7:0] fifo_data);
        (* parallel_case, full_case *)
        case (fifo_state_m)
            STATE_FIFO_CMD: begin
                handle_cmd_task (fifo_data[7:6], fifo_data[5:0]);

                if (fifo_data[5:0] > 6'd0) begin
                    rd_payload_bytes <= fifo_data[5:0];
                    last_fifo_cmd <= fifo_data[7:6];
                    fifo_state_m <= STATE_FIFO_PAYLOAD;
                end
            end

            STATE_FIFO_PAYLOAD: begin
                handle_payload_task (last_fifo_cmd, fifo_data);

                rd_payload_bytes <= rd_payload_bytes - 2'd1;

                if (rd_payload_bytes == 2'd1) begin
                    fifo_state_m <= STATE_FIFO_CMD;
                end
            end
        endcase
    endtask

    //==================================================================================================================
    // The FIFO writter
    //==================================================================================================================
    task write_buffer_task;
        if (wr_data[0][5:0] + 6'd1 == wr_data_index) begin
            wr_out_fifo_en_o <= 1'b0;
            state_m <= next_state_m;
        end else begin
            if (~wr_out_fifo_full_i && ~wr_out_fifo_afull_i) begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t<--- [STATE_WR_BUFFER] Wr OUT [%d]: %d. \033[0;0m",
                                wr_data_index, wr_data[wr_data_index]);
`endif
                wr_out_fifo_en_o <= 1'b1;
                wr_out_fifo_data_o <= wr_data[wr_data_index];

                wr_data_index <= wr_data_index + 6'd1;
            end else begin
                wr_out_fifo_en_o <= 1'b0;
            end
        end
    endtask

    //==================================================================================================================
    // The test completed successfully
    //==================================================================================================================
    task test_ok_task;
`ifdef D_CTRL
        $display ($time, "\033[0;36m CTRL:\t==== TEST OK ====. \033[0;0m");
`endif
        wr_data_index <= 6'd0;
        wr_data[0] <= {`CMD_TEST_STOPPED, 6'h1};
        wr_data[1] <= `TEST_ERROR_NONE;

        state_m <= STATE_WR_BUFFER;
        next_state_m <= STATE_RD;
    endtask

    //==================================================================================================================
    // The test fail
    //==================================================================================================================
    task test_fail_task;
`ifdef D_CTRL
        $display ($time, "\033[0;36m CTRL:\t==== TEST FAILED [code: %d] ====. \033[0;0m", wr_data[1]);
`endif
        led_ctrl_err_o <= 1'b1;

        state_m <= STATE_WR_BUFFER;
        next_state_m <= STATE_IDLE;
    endtask

    //==================================================================================================================
    // FIFO read/write
    //==================================================================================================================
    always @(posedge clk, posedge reset_i) begin
        if (reset_i) begin
`ifdef D_CTRL
            $display ($time, "\033[0;36m CTRL:\t-- Reset. \033[0;0m");
`endif
            rd_in_fifo_en_o <= 1'b0;
            wr_out_fifo_en_o <= 1'b0;

            state_m <= STATE_RD;
            fifo_state_m <= STATE_FIFO_CMD;

            led_ctrl_err_o <= 1'b0;
        end else begin
            (* parallel_case, full_case *)
            case (state_m)
                STATE_IDLE: begin
                end

                STATE_RD: begin
                    if (~rd_in_fifo_empty_i) begin
                        // Read data out of the FIFO
                        rd_in_fifo_en_o <= 1'b1;
                        if (rd_in_fifo_en_o) begin
                            read_data_task (rd_in_fifo_data_i);
                        end
                    end else begin
                        // Stop reading
                        rd_in_fifo_en_o <= 1'b0;
                    end
                end

                STATE_WR: begin
                    write_data_task;
                end

                STATE_WR_BUFFER: begin
                    write_buffer_task (STATE_RD);
                end
            endcase
        end
    end
endmodule

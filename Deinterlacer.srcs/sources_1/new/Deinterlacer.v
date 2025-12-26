`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Create Date: 26.12.2025 09:59:31
// Design Name: 
// Module Name: Deinterlacer
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Bob Deinterlacer for initial version of the upscaler. 
//              To be switched out with adaptive at somepoint.
// 
// Revision 1.0 - Initial Version
// 
//////////////////////////////////////////////////////////////////////////////////

module Deinterlacer_bob #(
    parameter PIXEL_WIDTH = 24,
    parameter MAX_WIDTH   = 1920
)(
    input  wire clk,
    input  wire rst_n,
    
    // Input field
    input  wire                   in_valid,
    input  wire [PIXEL_WIDTH-1:0] in_pixel,
    input  wire                   in_line_start,
    input  wire                   in_field_start,
    input  wire                   in_field_id, // 0=even, 1=odd
    input  wire                   in_interlaced,
    
    // Output progressive frame
    output reg                    out_valid,
    output reg [PIXEL_WIDTH-1:0]  out_pixel,
    output reg                    out_line_start,
    output reg                    out_frame_start
);

    reg [PIXEL_WIDTH-1:0] line_buffer [0:MAX_WIDTH-1];
    reg [$clog2(MAX_WIDTH)-1:0] line_addr;
    reg repeat_line;
    
    always @(posedge clk) begin
        if (in_interlaced) begin
            // Bob mode: repeat each line twice
            if (in_valid) begin
                line_buffer[line_addr] <= in_pixel;
                line_addr <= line_addr + 1;
                
                out_valid      <= 1'b1;
                out_pixel      <= in_pixel;
                out_line_start <= in_line_start;
                out_frame_start <= in_field_start;
                repeat_line    <= 1'b1;
            end else if (repeat_line && line_addr > 0) begin
                // Output duplicate line from buffer
                out_valid      <= 1'b1;
                out_pixel      <= line_buffer[line_addr-1];
                out_line_start <= 1'b1;
                out_frame_start <= 1'b0;
                repeat_line    <= 1'b0;
            end
        end else begin
            // Progressive passthrough
            out_valid       <= in_valid;
            out_pixel       <= in_pixel;
            out_line_start  <= in_line_start;
            out_frame_start <= in_field_start;
        end
        
        if (in_line_start)
            line_addr <= 0;
    end
    
    assign pixel_valid = (h_count >= h_sync_len + h_backporch) && (h_count < h_sync_len + h_backporch + h_active) &&
                            (v_count >= v_sync_len + v_backporch) && 
                            (v_count < v_sync_len + v_backporch + v_active);

    assign line_start   = (h_count == h_sync_len + h_backporch);
    assign frame_start  = line_start && (v_count == v_sync_len + v_backporch);

endmodule


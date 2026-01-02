`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// VPU Test Pattern Generator - 480i
// Generates a continuous 480i interlaced test signal in VPU format
// Outputs color bars or gradient pattern for visual verification
//////////////////////////////////////////////////////////////////////////////////

module VPU_test_pattern_480i #(
    parameter PIXEL_WIDTH = 24,
    parameter H_ACTIVE = 720,
    parameter V_ACTIVE_FIELD = 240,  // Lines per field (480i = 240 per field)
    parameter PATTERN_TYPE = 0       // 0 = color bars, 1 = gradient, 2 = grid
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Control
    input  wire                     enable,
    input  wire [1:0]               pattern_sel,  // Runtime pattern selection
    
    // VPU Output Stream
    output reg                      VPU_out_valid,
    input  wire                     VPU_out_ready,
    output reg [PIXEL_WIDTH-1:0]    VPU_out_pixel,
    output reg                      VPU_out_line_start,
    output reg                      VPU_out_frame_start,
    output reg                      VPU_out_interlaced,
    output reg                      VPU_out_field_id,
    output reg [11:0]               VPU_out_h_active,
    output reg [11:0]               VPU_out_v_active
);

    // Counters
    reg [11:0] h_count;
    reg [11:0] v_count;
    reg        field_id;
    reg        frame_active;
    
    // State machine
    localparam IDLE       = 2'b00;
    localparam LINE_START = 2'b01;
    localparam ACTIVE     = 2'b10;
    localparam LINE_END   = 2'b11;
    
    reg [1:0] state;
    
    // Blanking intervals (simplified for testing)
    localparam H_BLANK = 16;   // Cycles between lines
    localparam V_BLANK = 4;    // Lines between fields
    
    reg [7:0] blank_count;
    
    // Handshake
    wire handshake = VPU_out_valid && VPU_out_ready;
    
    // Color bar colors (8 bars across 720 pixels = 90 pixels each)
    // White, Yellow, Cyan, Green, Magenta, Red, Blue, Black
    function [23:0] get_color_bar;
        input [11:0] x_pos;
        reg [2:0] bar_index;
        begin
            bar_index = x_pos / (H_ACTIVE / 8);
            case (bar_index)
                3'd0: get_color_bar = 24'hFFFFFF;  // White
                3'd1: get_color_bar = 24'hFFFF00;  // Yellow
                3'd2: get_color_bar = 24'h00FFFF;  // Cyan
                3'd3: get_color_bar = 24'h00FF00;  // Green
                3'd4: get_color_bar = 24'hFF00FF;  // Magenta
                3'd5: get_color_bar = 24'hFF0000;  // Red
                3'd6: get_color_bar = 24'h0000FF;  // Blue
                3'd7: get_color_bar = 24'h000000;  // Black
                default: get_color_bar = 24'h000000;
            endcase
        end
    endfunction
    
    // Gradient pattern
    function [23:0] get_gradient;
        input [11:0] x_pos;
        input [11:0] y_pos;
        input        field;
        reg [7:0] r, g, b;
        begin
            r = (x_pos * 255) / H_ACTIVE;
            g = ((y_pos * 2 + field) * 255) / (V_ACTIVE_FIELD * 2);
            b = 255 - r;
            get_gradient = {r, g, b};
        end
    endfunction
    
    // Grid pattern (useful for checking alignment)
    function [23:0] get_grid;
        input [11:0] x_pos;
        input [11:0] y_pos;
        input        field;
        reg [11:0] actual_y;
        begin
            actual_y = y_pos * 2 + field;
            // Draw white grid lines every 32 pixels
            if ((x_pos % 32 == 0) || (actual_y % 32 == 0))
                get_grid = 24'hFFFFFF;
            // Draw red border
            else if (x_pos == 0 || x_pos == H_ACTIVE-1 || actual_y == 0 || actual_y == V_ACTIVE_FIELD*2-1)
                get_grid = 24'hFF0000;
            else
                get_grid = 24'h202020;  // Dark gray background
        end
    endfunction
    
    // Pattern selection
    function [23:0] get_pixel;
        input [11:0] x_pos;
        input [11:0] y_pos;
        input        field;
        input [1:0]  pattern;
        begin
            case (pattern)
                2'd0: get_pixel = get_color_bar(x_pos);
                2'd1: get_pixel = get_gradient(x_pos, y_pos, field);
                2'd2: get_pixel = get_grid(x_pos, y_pos, field);
                2'd3: begin
                    // Unique pixel pattern - encodes position in pixel value
                    // Useful for debugging data integrity
                    get_pixel = {y_pos[7:0], x_pos[11:4], field, x_pos[2:0], 4'hA};
                end
                default: get_pixel = 24'h000000;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= IDLE;
            h_count            <= 0;
            v_count            <= 0;
            field_id           <= 0;
            frame_active       <= 0;
            blank_count        <= 0;
            VPU_out_valid      <= 1'b0;
            VPU_out_pixel      <= 24'h0;
            VPU_out_line_start <= 1'b0;
            VPU_out_frame_start <= 1'b0;
            VPU_out_interlaced <= 1'b1;
            VPU_out_field_id   <= 1'b0;
            VPU_out_h_active   <= H_ACTIVE;
            VPU_out_v_active   <= V_ACTIVE_FIELD;
        end else begin
            // Default outputs
            VPU_out_interlaced <= 1'b1;
            VPU_out_h_active   <= H_ACTIVE;
            VPU_out_v_active   <= V_ACTIVE_FIELD;
            VPU_out_field_id   <= field_id;
            
            case (state)
                IDLE: begin
                    VPU_out_valid       <= 1'b0;
                    VPU_out_line_start  <= 1'b0;
                    VPU_out_frame_start <= 1'b0;
                    
                    if (enable) begin
                        state        <= LINE_START;
                        h_count      <= 0;
                        v_count      <= 0;
                        field_id     <= 0;
                        frame_active <= 1;
                    end
                end
                
                LINE_START: begin
                    // Output first pixel with line_start (and frame_start if first line of field 0)
                    VPU_out_valid       <= 1'b1;
                    VPU_out_pixel       <= get_pixel(0, v_count, field_id, pattern_sel);
                    VPU_out_line_start  <= 1'b1;
                    VPU_out_frame_start <= (v_count == 0) && (field_id == 0);
                    
                    if (handshake) begin
                        state              <= ACTIVE;
                        h_count            <= 1;
                        VPU_out_line_start <= 1'b0;
                        VPU_out_frame_start <= 1'b0;
                    end
                end
                
                ACTIVE: begin
                    VPU_out_line_start  <= 1'b0;
                    VPU_out_frame_start <= 1'b0;
                    
                    if (!VPU_out_valid || handshake) begin
                        if (h_count < H_ACTIVE) begin
                            VPU_out_valid <= 1'b1;
                            VPU_out_pixel <= get_pixel(h_count, v_count, field_id, pattern_sel);
                            h_count       <= h_count + 1;
                        end else begin
                            // End of line
                            VPU_out_valid <= 1'b0;
                            state         <= LINE_END;
                            blank_count   <= 0;
                        end
                    end
                end
                
                LINE_END: begin
                    VPU_out_valid <= 1'b0;
                    
                    // Horizontal blanking period
                    if (blank_count < H_BLANK) begin
                        blank_count <= blank_count + 1;
                    end else begin
                        // Move to next line
                        if (v_count < V_ACTIVE_FIELD - 1) begin
                            v_count <= v_count + 1;
                            state   <= LINE_START;
                        end else begin
                            // End of field - switch fields
                            v_count <= 0;
                            
                            if (field_id == 0) begin
                                field_id <= 1;
                                state    <= LINE_START;
                            end else begin
                                // End of frame (both fields done)
                                field_id <= 0;
                                
                                if (enable) begin
                                    state <= LINE_START;  // Start next frame
                                end else begin
                                    state        <= IDLE;
                                    frame_active <= 0;
                                end
                            end
                        end
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
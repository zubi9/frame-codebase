/*
 * This file is a part of: https://github.com/brilliantlabsAR/frame-codebase
 *
 * Authored by: Rohit Rathnam / Silicon Witchery AB (rohit@siliconwitchery.com)
 *              Raj Nakarja / Brilliant Labs Limited (raj@brilliant.xyz)
 *
 * CERN Open Hardware Licence Version 2 - Permissive
 *
 * Copyright © 2023 Brilliant Labs Limited
 */

`ifndef RADIANT
`include "modules/camera/crop.sv"
`include "modules/camera/debayer.sv"
`include "modules/camera/image_buffer.sv"
`include "modules/camera/metering.sv"
`endif

`ifdef TESTBENCH
`include "modules/camera/testbenches/image_gen.sv"
`endif

module camera (
    input logic global_reset_n_in,
    
    input logic spi_clock_in, // 72MHz
    input logic spi_reset_n_in,

    input logic pixel_clock_in, // 36MHz
    input logic pixel_reset_n_in,

    inout wire mipi_clock_p_in,
    inout wire mipi_clock_n_in,
    inout wire mipi_data_p_in,
    inout wire mipi_data_n_in,

    input logic [7:0] op_code_in,
    input logic op_code_valid_in,
    input logic [7:0] operand_in,
    input logic operand_valid_in,
    input integer operand_count_in,
    output logic [7:0] response_out,
    output logic response_valid_out
);

// Registers to hold the current command operations
logic capture_flag;
logic capture_in_progress_flag;

// TODO make capture_size dynamic once we have adjustable resolution
logic [15:0] capture_size = 200 * 200;
logic [15:0] bytes_read;

logic [15:0] bytes_remaining;
assign bytes_remaining = capture_size - bytes_read;

logic [15:0] buffer_read_address;
logic [7:0] buffer_read_data;
assign buffer_read_address = bytes_read;

logic [7:0] red_metering;
logic [7:0] green_metering;
logic [7:0] blue_metering;

logic last_op_code_valid_in;
logic last_operand_valid_in;

// Handle op-codes as they come in
always_ff @(posedge spi_clock_in) begin
    
    if (spi_reset_n_in == 0) begin
        response_out <= 0;
        response_valid_out <= 0;
        capture_flag <= 0;
        bytes_read <= 0;
        last_op_code_valid_in <= 0;
        last_operand_valid_in <= 0;
    end

    else begin

        last_op_code_valid_in <= op_code_valid_in;
        last_operand_valid_in <= operand_valid_in;

        // Clear capture flag once it is in process
        if (capture_in_progress_flag == 1) begin
            capture_flag <= 0;  
        end
        
        if (op_code_valid_in) begin

            case (op_code_in)

                // Capture
                'h20: begin
                    if (capture_in_progress_flag == 0) begin
                        capture_flag <= 1;
                        bytes_read <= 0;
                    end
                end

                // Bytes available
                'h21: begin
                    case (operand_count_in)
                        0: response_out <= bytes_remaining[15:8];
                        1: response_out <= bytes_remaining[7:0];
                    endcase

                    response_valid_out <= 1;
                end

                // Read data
                'h22: begin
                    response_out <= buffer_read_data;
                    response_valid_out <= 1;

                    if (last_operand_valid_in == 0 && operand_valid_in == 1) begin
                        bytes_read <= bytes_read + 1;
                    end
                end

                // Metering
                'h25: begin
                    case (operand_count_in)
                        0: response_out <= red_metering;
                        1: response_out <= green_metering;
                        2: response_out <= blue_metering;
                    endcase

                    response_valid_out <= 1;
                end

            endcase

        end

        else begin
            response_valid_out <= 0;
        end

    end

end

// Capture command logic
logic [1:0] cropped_frame_valid_edge_monitor;
logic cropped_frame_valid;

always_ff @(posedge spi_clock_in) begin
    if (spi_reset_n_in == 0) begin
        capture_in_progress_flag <= 0;
        cropped_frame_valid_edge_monitor <= 0;
    end

    else begin
        cropped_frame_valid_edge_monitor <= {cropped_frame_valid_edge_monitor[0],
                                             cropped_frame_valid};

        if (capture_flag && cropped_frame_valid_edge_monitor == 'b01) begin
            capture_in_progress_flag <= 1;
        end

        if (cropped_frame_valid_edge_monitor == 'b10) begin
            capture_in_progress_flag <= 0;
        end
    end
end

`ifdef RADIANT

logic mipi_byte_clock;
logic mipi_byte_reset_n;

logic mipi_payload_enable_metastable /* synthesis syn_keep=1 nomerge=""*/;
logic mipi_payload_enable /* synthesis syn_keep=1 nomerge=""*/;

logic [7:0] mipi_payload_metastable /* synthesis syn_keep=1 nomerge=""*/;
logic [7:0] mipi_payload /* synthesis syn_keep=1 nomerge=""*/;

logic mipi_sp_enable_metastable /* synthesis syn_keep=1 nomerge=""*/;
logic mipi_sp_enable /* synthesis syn_keep=1 nomerge=""*/;

logic mipi_lp_av_enable_metastable /* synthesis syn_keep=1 nomerge=""*/;
logic mipi_lp_av_enable /* synthesis syn_keep=1 nomerge=""*/;

logic [15:0] mipi_word_count /* synthesis syn_keep=1 nomerge=""*/;
logic [5:0] mipi_datatype;

reset_sync mipi_byte_clock_reset_sync (
    .clock_in(mipi_byte_clock),
    .async_reset_n_in(global_reset_n_in),
    .sync_reset_n_out(mipi_byte_reset_n)
);

csi2_receiver_ip csi2_receiver_ip (
    .clk_byte_o(),
    .clk_byte_hs_o(mipi_byte_clock),
    .clk_byte_fr_i(mipi_byte_clock),
    .reset_n_i(global_reset_n_in),
    .reset_byte_fr_n_i(mipi_byte_reset_n),
    .clk_p_io(mipi_clock_p_in),
    .clk_n_io(mipi_clock_n_in),
    .d_p_io(mipi_data_p_in),
    .d_n_io(mipi_data_n_in),
    .payload_en_o(mipi_payload_enable_metastable),
    .payload_o(mipi_payload_metastable),
    .tx_rdy_i(1'b1),
    .pd_dphy_i(~global_reset_n_in),
    .dt_o(mipi_datatype),
    .wc_o(mipi_word_count),
    .ref_dt_i(6'h2B),
    .sp_en_o(mipi_sp_enable_metastable),
    .lp_en_o(),
    .lp_av_en_o(mipi_lp_av_enable_metastable)
);

always @(posedge mipi_byte_clock or negedge mipi_byte_reset_n) begin

    if (!mipi_byte_reset_n) begin
        mipi_payload_enable <= 0;
        mipi_payload <= 0;
        mipi_sp_enable <= 0;
        mipi_lp_av_enable <= 0;
    end

    else begin
        mipi_payload_enable <= mipi_payload_enable_metastable;
        mipi_payload <= mipi_payload_metastable;
        mipi_sp_enable <= mipi_sp_enable_metastable;
        mipi_lp_av_enable <= mipi_lp_av_enable_metastable;
    end

end

logic byte_to_pixel_frame_valid /* synthesis syn_keep=1 nomerge=""*/;
logic byte_to_pixel_line_valid /* synthesis syn_keep=1 nomerge=""*/;
logic [9:0] byte_to_pixel_data /* synthesis syn_keep=1 nomerge=""*/;

byte_to_pixel_ip byte_to_pixel_ip (
    .reset_byte_n_i(mipi_byte_reset_n),
    .clk_byte_i(mipi_byte_clock),
    .sp_en_i(mipi_sp_enable),
    .dt_i(mipi_datatype),
    .lp_av_en_i(mipi_lp_av_enable),
    .payload_en_i(mipi_payload_enable),
    .payload_i(mipi_payload),
    .wc_i(mipi_word_count),
    .reset_pixel_n_i(pixel_reset_n_in),
    .clk_pixel_i(pixel_clock_in),
    .fv_o(byte_to_pixel_frame_valid),
    .lv_o(byte_to_pixel_line_valid),
    .pd_o(byte_to_pixel_data)
);

`else // RADIANT

logic byte_to_pixel_frame_valid;
logic byte_to_pixel_line_valid;
logic [9:0] byte_to_pixel_data;

`endif // RADIANT

`ifdef TESTBENCH // TESTBENCH

image_gen image_gen (
    .clock_in(pixel_clock_in),
    .reset_n_in(pixel_reset_n_in),

    .bayer_data_out(byte_to_pixel_data),
    .line_valid_out(byte_to_pixel_line_valid),
    .frame_valid_out(byte_to_pixel_frame_valid)
);

`endif // TESTBENCH

logic [9:0] debayered_red_data;
logic [9:0] debayered_green_data;
logic [9:0] debayered_blue_data;
logic debayered_line_valid;
logic debayered_frame_valid;

debayer debayer (
    .clock_in(pixel_clock_in),
    .reset_n_in(pixel_reset_n_in),

    .bayer_data_in(byte_to_pixel_data),
    .line_valid_in(byte_to_pixel_line_valid),
    .frame_valid_in(byte_to_pixel_frame_valid),

    .red_data_out(debayered_red_data),
    .green_data_out(debayered_green_data),
    .blue_data_out(debayered_blue_data),
    .line_valid_out(debayered_line_valid),
    .frame_valid_out(debayered_frame_valid)
);

metering metering (
    .clock_in(pixel_clock_in),
    .reset_n_in(pixel_reset_n_in),

    .red_data_in(debayered_red_data),
    .green_data_in(debayered_green_data),
    .blue_data_in(debayered_blue_data),
    .line_valid_in(debayered_line_valid),
    .frame_valid_in(debayered_frame_valid),

    .red_metering_out(red_metering),
    .green_metering_out(green_metering),
    .blue_metering_out(blue_metering)
);

logic [9:0] cropped_red_data;
logic [9:0] cropped_green_data;
logic [9:0] cropped_blue_data;
logic cropped_line_valid;

crop 
`ifndef TESTBENCH
#(
    .X_CROP_START(542),
    .X_CROP_END(742),
    .Y_CROP_START(260),
    .Y_CROP_END(460)
) 
`endif
crop (
    .clock_in(pixel_clock_in),
    .reset_n_in(pixel_reset_n_in),

    .red_data_in(debayered_red_data),
    .green_data_in(debayered_green_data),
    .blue_data_in(debayered_blue_data),
    .line_valid_in(debayered_line_valid),
    .frame_valid_in(debayered_frame_valid),

    .red_data_out(cropped_red_data),
    .green_data_out(cropped_green_data),
    .blue_data_out(cropped_blue_data),
    .line_valid_out(cropped_line_valid),
    .frame_valid_out(cropped_frame_valid)
);

logic [15:0] buffer_write_address;

always_ff @(posedge pixel_clock_in) begin

    if (pixel_reset_n_in == 0) begin
        buffer_write_address <= 0;
    end

    else begin
        if (cropped_frame_valid == 0) begin
            buffer_write_address <= 0;
        end
        else if (cropped_frame_valid && cropped_line_valid) begin
            buffer_write_address <= buffer_write_address + 1;
        end
    end

end

image_buffer image_buffer (
    .write_clock_in(pixel_clock_in),
    .read_clock_in(spi_clock_in),
    .write_reset_n_in(pixel_reset_n_in),
    .read_reset_n_in(spi_reset_n_in),
    .write_address_in(buffer_write_address),
    .read_address_in(buffer_read_address),
    .write_data_in({cropped_red_data[9:7], cropped_green_data[9:7], cropped_blue_data[9:8]}),
    .read_data_out(buffer_read_data),
    .write_read_n_in(cropped_frame_valid && cropped_line_valid && capture_in_progress_flag)
);

endmodule
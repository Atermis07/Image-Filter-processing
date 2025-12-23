`timescale 1ns/1ps
`include "parameter.v"

module tb_simulation;

// ============================================================
// 1. CÁC TÍN HIỆU ĐIỀU KHIỂN TỪ TCL CONSOLE
// ============================================================
reg [2:0] tcl_filter_sel; 
reg       tcl_preview_mode; 
reg       tcl_reset_n;
reg       tcl_feedback_trigger;

// ============================================================
// 2. INTERNAL SIGNALS
// ============================================================
reg HCLK;
wire vsync, hsync, enc_done;
wire [7:0] data_r, data_g, data_b; 
wire [7:0] data_r_1, data_g_1, data_b_1;
wire write_done;

integer k; 

// Tạo Clock 50MHz
initial begin
  HCLK = 0; forever #10 HCLK = ~HCLK; 
end

// ============================================================
// 3. KẾT NỐI MODULE (DUT)
// ============================================================

// --- Module Đọc ảnh (Input) ---
image_read #(
  .INFILE(`INPUTFILENAME) 
) u_image_read (
  .HCLK(HCLK),
  .HRESETn(tcl_reset_n),       
  .FILTER_SEL(tcl_filter_sel), 
  .VSYNC(vsync),
  .HSYNC(hsync),
  .ctrl_done(enc_done),
  .DATA_R0_OUT(data_r),   .DATA_G0_OUT(data_g),   .DATA_B0_OUT(data_b),
  .DATA_R1_OUT(data_r_1), .DATA_G1_OUT(data_g_1), .DATA_B1_OUT(data_b_1)
);

// --- Module Ghi ảnh (Output) ---
image_write u_image_write (
  .HCLK(HCLK),
  .HRESETn(tcl_reset_n),
  .HSYNC(hsync),
  .PREVIEW_MODE(tcl_preview_mode), 
  .DATA_R0(data_r),   .DATA_G0(data_g),   .DATA_B0(data_b),
  .DATA_R1(data_r_1), .DATA_G1(data_g_1), .DATA_B1(data_b_1),
  .ctrl_done(enc_done),
  .Write_Done(write_done)
);

// ============================================================
// 4. LOGIC FEEDBACK
// ============================================================
always @(posedge tcl_feedback_trigger) begin
    $display("\n[FEEDBACK] Bat dau copy du lieu tu Image Write -> Image Read...");
    
    // Duyệt qua 768x512 pixel
    for (k = 0; k < 768 * 512; k = k + 1) begin
        u_image_read.org_B[k] = u_image_write.out_BMP[k*3 + 0];
        u_image_read.org_G[k] = u_image_write.out_BMP[k*3 + 1];
        u_image_read.org_R[k] = u_image_write.out_BMP[k*3 + 2];
    end
    
    $display("[FEEDBACK] -> Da cap nhat xong! Lan chay tiep theo se xu ly tren anh moi nay.\n");
end

// ============================================================
// 5. KHỞI TẠO & HƯỚNG DẪN
// ============================================================
initial begin
  tcl_reset_n = 0; 
  tcl_filter_sel = 0; 
  tcl_preview_mode = 0;
  tcl_feedback_trigger = 0;

  $display("\n=======================================================");
  $display("  HE THOMG MO PHONG XU LY ANH (FIXED)   ");
  $display("=======================================================");
  $stop; 
end

endmodule

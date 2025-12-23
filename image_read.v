`include "parameter.v"
module image_read #(
  parameter WIDTH          = 768,
  parameter HEIGHT         = 512,
  parameter INFILE         = `INPUTFILENAME,
  parameter START_UP_DELAY = 100,
  parameter HSYNC_DELAY    = 160,
  parameter VALUE          = 100,
  parameter THRESHOLD      = 90,
  parameter SIGN           = 1,
  localparam ALPHA         = 1,
  localparam KYR = 306, localparam KYG = 601, localparam KYB = 116
)(
  input  HCLK,
  input  HRESETn,
  input  [2:0] FILTER_SEL, 
  output VSYNC,
  output reg HSYNC,
  output ctrl_done,
  output reg [7:0] DATA_R0_OUT, DATA_G0_OUT, DATA_B0_OUT,
  output reg [7:0] DATA_R1_OUT, DATA_G1_OUT, DATA_B1_OUT
);

parameter sizeOfLengthReal = WIDTH * HEIGHT * 3;
localparam ST_IDLE  = 2'b00, ST_VSYNC = 2'b01, ST_HSYNC = 2'b10, ST_DATA  = 2'b11;

reg [1:0] cstate, nstate;
reg start;
reg HRESETn_d;
reg ctrl_vsync_run, ctrl_hsync_run, ctrl_data_run;
reg [8:0] ctrl_vsync_cnt, ctrl_hsync_cnt;

reg [7:0] total_memory [0 : sizeOfLengthReal-1];
reg [7:0] org_R [0 : WIDTH*HEIGHT - 1];
reg [7:0] org_G [0 : WIDTH*HEIGHT - 1];
reg [7:0] org_B [0 : WIDTH*HEIGHT - 1];

integer i, j;
reg [10:0] row, col;
reg [18:0] data_count;

integer tempR0, tempR1, tempG0, tempG1, tempB0, tempB1;
integer value, value1, value2, value4;
integer gy, gx, rr, cc, cc1;
reg [7:0] med_row_R [0:4], med_row_G [0:4], med_row_B [0:4];
reg [7:0] win_R [0:4][0:4], win_G [0:4][0:4], win_B [0:4][0:4];

integer sobel_gx [0:8], sobel_gy [0:8]; 
integer sum_gx, sum_gy, mag0, mag1;
reg [7:0] gray_win [0:8]; 
integer y_tmp, idx;

reg [7:0] r0_res, g0_res, b0_res, r1_res, g1_res, b1_res;

// --- FUNCTION MEDIAN ---
function [7:0] median_of_5;
  input [7:0] d0, d1, d2, d3, d4;
  reg [7:0] t;
  reg [7:0] a0, a1, a2, a3, a4;
  begin
    a0 = d0; a1 = d1; a2 = d2; a3 = d3; a4 = d4;
    if(a0 > a1) begin t=a0; a0=a1; a1=t; end
    if(a3 > a4) begin t=a3; a3=a4; a4=t; end
    if(a0 > a3) begin t=a0; a0=a3; a3=t; end
    if(a1 > a4) begin t=a1; a1=a4; a4=t; end
    if(a1 > a2) begin t=a1; a1=a2; a2=t; end
    if(a2 > a3) begin t=a2; a2=a3; a3=t; end
    if(a1 > a2) begin t=a1; a1=a2; a2=t; end
    median_of_5 = a2; 
  end
endfunction

// --- INIT DATA ---
initial begin
  $readmemh(INFILE, total_memory, 0, sizeOfLengthReal-1);
  
  // Init Sobel Kernels
  sobel_gx[0] = -1; sobel_gx[1] = 0; sobel_gx[2] = 1;
  sobel_gx[3] = -2; sobel_gx[4] = 0; sobel_gx[5] = 2;
  sobel_gx[6] = -1; sobel_gx[7] = 0; sobel_gx[8] = 1;
  
  sobel_gy[0] =  1; sobel_gy[1] =  2; sobel_gy[2] =  1;
  sobel_gy[3] =  0; sobel_gy[4] =  0; sobel_gy[5] =  0;
  sobel_gy[6] = -1; sobel_gy[7] = -2; sobel_gy[8] = -1;
end

initial begin
  #10; 
  for (i = 0; i < HEIGHT; i = i + 1) begin
    for (j = 0; j < WIDTH; j = j + 1) begin
      org_R[WIDTH*i + j] = total_memory[WIDTH*3*(HEIGHT - i - 1) + 3*j + 0];
      org_G[WIDTH*i + j] = total_memory[WIDTH*3*(HEIGHT - i - 1) + 3*j + 1];
      org_B[WIDTH*i + j] = total_memory[WIDTH*3*(HEIGHT - i - 1) + 3*j + 2];
    end
  end
end

// --- FSM CONTROL ---
always @(posedge HCLK or negedge HRESETn) begin
  if (!HRESETn) begin start <= 0; HRESETn_d <= 0; end 
  else begin HRESETn_d <= HRESETn; if (HRESETn && !HRESETn_d) start <= 1'b1; else start <= 1'b0; end
end
always @(posedge HCLK or negedge HRESETn) begin
  if (!HRESETn) cstate <= ST_IDLE; else cstate <= nstate;
end
always @(*) begin
  case (cstate)
    ST_IDLE:   nstate = start ? ST_VSYNC : ST_IDLE;
    ST_VSYNC:  nstate = (ctrl_vsync_cnt == START_UP_DELAY) ? ST_HSYNC : ST_VSYNC;
    ST_HSYNC:  nstate = (ctrl_hsync_cnt == HSYNC_DELAY) ? ST_DATA : ST_HSYNC;
    ST_DATA:   nstate = ctrl_done ? ST_IDLE : (col == WIDTH - 2) ? ST_HSYNC : ST_DATA;
    default:   nstate = ST_IDLE;
  endcase
end
always @(*) begin
  ctrl_vsync_run = 0; ctrl_hsync_run = 0; ctrl_data_run  = 0;
  case (cstate)
    ST_VSYNC: ctrl_vsync_run = 1;
    ST_HSYNC: ctrl_hsync_run = 1;
    ST_DATA:  ctrl_data_run = 1;
  endcase
end
always @(posedge HCLK or negedge HRESETn) begin
  if (!HRESETn) begin ctrl_vsync_cnt <= 0; ctrl_hsync_cnt <= 0; end 
  else begin
    if (ctrl_vsync_run) ctrl_vsync_cnt <= ctrl_vsync_cnt + 1; else ctrl_vsync_cnt <= 0;
    if (ctrl_hsync_run) ctrl_hsync_cnt <= ctrl_hsync_cnt + 1; else ctrl_hsync_cnt <= 0;
  end
end
always @(posedge HCLK or negedge HRESETn) begin
  if(!HRESETn) begin row <= 0; col <= 0; end 
  else if (ctrl_data_run) begin
    if (col == WIDTH - 2) begin row <= row + 1; col <= 0; end 
    else begin col <= col + 2; end
  end
end
always @(posedge HCLK or negedge HRESETn) begin
  if (!HRESETn) data_count <= 0; else if (ctrl_data_run) data_count <= data_count + 1;
end
assign VSYNC = ctrl_vsync_run;
assign ctrl_done = (data_count == (WIDTH*HEIGHT/2) - 1);

// --- PROCESSING LOGIC ---
always @(*) begin
  HSYNC = 0;
  DATA_R0_OUT = 0; DATA_G0_OUT = 0; DATA_B0_OUT = 0;
  DATA_R1_OUT = 0; DATA_G1_OUT = 0; DATA_B1_OUT = 0;
  r0_res = 0; g0_res = 0; b0_res = 0;
  r1_res = 0; g1_res = 0; b1_res = 0;

  if (ctrl_data_run) begin
    HSYNC = 1'b1;
    case (FILTER_SEL)
        // 1. BRIGHTNESS
        3'd1: begin
            if (SIGN == 1) begin
                tempR0 = org_R[WIDTH*row + col] + VALUE; r0_res = (tempR0 > 255) ? 255 : tempR0;
                tempG0 = org_G[WIDTH*row + col] + VALUE; g0_res = (tempG0 > 255) ? 255 : tempG0;
                tempB0 = org_B[WIDTH*row + col] + VALUE; b0_res = (tempB0 > 255) ? 255 : tempB0;
                tempR1 = org_R[WIDTH*row + col+1] + VALUE; r1_res = (tempR1 > 255) ? 255 : tempR1;
                tempG1 = org_G[WIDTH*row + col+1] + VALUE; g1_res = (tempG1 > 255) ? 255 : tempG1;
                tempB1 = org_B[WIDTH*row + col+1] + VALUE; b1_res = (tempB1 > 255) ? 255 : tempB1;
            end else begin
                tempR0 = org_R[WIDTH*row + col] - VALUE; r0_res = (tempR0 < 0) ? 0 : tempR0;
                tempG0 = org_G[WIDTH*row + col] - VALUE; g0_res = (tempG0 < 0) ? 0 : tempG0;
                tempB0 = org_B[WIDTH*row + col] - VALUE; b0_res = (tempB0 < 0) ? 0 : tempB0;
                tempR1 = org_R[WIDTH*row + col+1] - VALUE; r1_res = (tempR1 < 0) ? 0 : tempR1;
                tempG1 = org_G[WIDTH*row + col+1] - VALUE; g1_res = (tempG1 < 0) ? 0 : tempG1;
                tempB1 = org_B[WIDTH*row + col+1] - VALUE; b1_res = (tempB1 < 0) ? 0 : tempB1;
            end
        end
        // 2. INVERT
        3'd2: begin
             value2 = (org_R[WIDTH*row + col] + org_G[WIDTH*row + col] + org_B[WIDTH*row + col]) / 3;
             r0_res = 255 - value2; g0_res = 255 - value2; b0_res = 255 - value2;
             value4 = (org_R[WIDTH*row + col+1] + org_G[WIDTH*row + col+1] + org_B[WIDTH*row + col+1]) / 3;
             r1_res = 255 - value4; g1_res = 255 - value4; b1_res = 255 - value4;
        end
        // 3. THRESHOLD
        3'd3: begin
             value = (org_R[WIDTH*row + col] + org_G[WIDTH*row + col] + org_B[WIDTH*row + col]) / 3;
             if (value > THRESHOLD) {r0_res, g0_res, b0_res} = {8'hFF, 8'hFF, 8'hFF};
             else {r0_res, g0_res, b0_res} = {8'h00, 8'h00, 8'h00};
             value1 = (org_R[WIDTH*row + col+1] + org_G[WIDTH*row + col+1] + org_B[WIDTH*row + col+1]) / 3;
             if (value1 > THRESHOLD) {r1_res, g1_res, b1_res} = {8'hFF, 8'hFF, 8'hFF};
             else {r1_res, g1_res, b1_res} = {8'h00, 8'h00, 8'h00};
        end
        // 5. MEDIAN
        3'd5: begin
            // Pixel 0
            for (gy=-2; gy<=2; gy=gy+1) begin
                rr = $signed(row) + gy;
                for (gx=-2; gx<=2; gx=gx+1) begin
                   cc = $signed(col) + gx;
                   if (rr>=0 && rr<HEIGHT && cc>=0 && cc<WIDTH) begin
                      win_R[gy+2][gx+2] = org_R[WIDTH*rr + cc];
                      win_G[gy+2][gx+2] = org_G[WIDTH*rr + cc];
                      win_B[gy+2][gx+2] = org_B[WIDTH*rr + cc];
                   end else begin
                      win_R[gy+2][gx+2]=0; win_G[gy+2][gx+2]=0; win_B[gy+2][gx+2]=0;
                   end
                end
            end
            for(i=0; i<5; i=i+1) begin
                 med_row_R[i] = median_of_5(win_R[i][0], win_R[i][1], win_R[i][2], win_R[i][3], win_R[i][4]);
                 med_row_G[i] = median_of_5(win_G[i][0], win_G[i][1], win_G[i][2], win_G[i][3], win_G[i][4]);
                 med_row_B[i] = median_of_5(win_B[i][0], win_B[i][1], win_B[i][2], win_B[i][3], win_B[i][4]);
            end
            r0_res = median_of_5(med_row_R[0], med_row_R[1], med_row_R[2], med_row_R[3], med_row_R[4]);
            g0_res = median_of_5(med_row_G[0], med_row_G[1], med_row_G[2], med_row_G[3], med_row_G[4]);
            b0_res = median_of_5(med_row_B[0], med_row_B[1], med_row_B[2], med_row_B[3], med_row_B[4]);
            
            // Pixel 1
            for (gy=-2; gy<=2; gy=gy+1) begin
                rr = $signed(row) + gy;
                for (gx=-2; gx<=2; gx=gx+1) begin
                   cc1 = $signed(col+1) + gx;
                   if (rr>=0 && rr<HEIGHT && cc1>=0 && cc1<WIDTH) begin
                      win_R[gy+2][gx+2] = org_R[WIDTH*rr + cc1];
                      win_G[gy+2][gx+2] = org_G[WIDTH*rr + cc1];
                      win_B[gy+2][gx+2] = org_B[WIDTH*rr + cc1];
                   end else begin
                      win_R[gy+2][gx+2]=0; win_G[gy+2][gx+2]=0; win_B[gy+2][gx+2]=0;
                   end
                end
            end
            for(i=0; i<5; i=i+1) begin
                 med_row_R[i] = median_of_5(win_R[i][0], win_R[i][1], win_R[i][2], win_R[i][3], win_R[i][4]);
                 med_row_G[i] = median_of_5(win_G[i][0], win_G[i][1], win_G[i][2], win_G[i][3], win_G[i][4]);
                 med_row_B[i] = median_of_5(win_B[i][0], win_B[i][1], win_B[i][2], win_B[i][3], win_B[i][4]);
            end
            r1_res = median_of_5(med_row_R[0], med_row_R[1], med_row_R[2], med_row_R[3], med_row_R[4]);
            g1_res = median_of_5(med_row_G[0], med_row_G[1], med_row_G[2], med_row_G[3], med_row_G[4]);
            b1_res = median_of_5(med_row_B[0], med_row_B[1], med_row_B[2], med_row_B[3], med_row_B[4]);
        end
        // 6. SOBEL
        3'd6: begin
             // Pixel 0
             idx = 0; 
             for (gy=-1;gy<=1;gy=gy+1) for(gx=-1;gx<=1;gx=gx+1) begin
                rr=$signed(row)+gy; cc=$signed(col)+gx;
                if ((rr >= 0) && (rr < HEIGHT) && (cc >= 0) && (cc < WIDTH)) begin
                   y_tmp = KYR*org_R[WIDTH*rr + cc] + KYG*org_G[WIDTH*rr + cc] + KYB*org_B[WIDTH*rr + cc];
                   gray_win[idx] = y_tmp[17:10];
                end else gray_win[idx] = 0;
                idx = idx + 1;
             end
             sum_gx = (gray_win[2] + (gray_win[5] << 1) + gray_win[8]) - (gray_win[0] + (gray_win[3] << 1) + gray_win[6]);
             sum_gy = (gray_win[0] + (gray_win[1] << 1) + gray_win[2]) - (gray_win[6] + (gray_win[7] << 1) + gray_win[8]);
             mag0 = (sum_gx < 0 ? -sum_gx : sum_gx) + (sum_gy < 0 ? -sum_gy : sum_gy);
             if (mag0 > 255) mag0 = 255;
             r0_res = mag0[7:0]; g0_res = mag0[7:0]; b0_res = mag0[7:0];

             // Pixel 1
             idx = 0; 
             for (gy=-1;gy<=1;gy=gy+1) for(gx=-1;gx<=1;gx=gx+1) begin
                rr=$signed(row)+gy; cc1=$signed(col+1)+gx;
                if ((rr >= 0) && (rr < HEIGHT) && (cc1 >= 0) && (cc1 < WIDTH)) begin
                   y_tmp = KYR*org_R[WIDTH*rr + cc1] + KYG*org_G[WIDTH*rr + cc1] + KYB*org_B[WIDTH*rr + cc1];
                   gray_win[idx] = y_tmp[17:10];
                end else gray_win[idx] = 0;
                idx = idx + 1;
             end
             sum_gx = (gray_win[2] + (gray_win[5] << 1) + gray_win[8]) - (gray_win[0] + (gray_win[3] << 1) + gray_win[6]);
             sum_gy = (gray_win[0] + (gray_win[1] << 1) + gray_win[2]) - (gray_win[6] + (gray_win[7] << 1) + gray_win[8]);
             mag1 = (sum_gx < 0 ? -sum_gx : sum_gx) + (sum_gy < 0 ? -sum_gy : sum_gy);
             if (mag1 > 255) mag1 = 255;
             r1_res = mag1[7:0]; g1_res = mag1[7:0]; b1_res = mag1[7:0];
        end
        // DEFAULT
        default: begin
             r0_res = org_R[WIDTH*row + col];   g0_res = org_G[WIDTH*row + col];   b0_res = org_B[WIDTH*row + col];
             r1_res = org_R[WIDTH*row + col+1]; g1_res = org_G[WIDTH*row + col+1]; b1_res = org_B[WIDTH*row + col+1];
        end
    endcase

    DATA_R0_OUT = r0_res; DATA_G0_OUT = g0_res; DATA_B0_OUT = b0_res;
    DATA_R1_OUT = r1_res; DATA_G1_OUT = g1_res; DATA_B1_OUT = b1_res;
  end 
end 
endmodule

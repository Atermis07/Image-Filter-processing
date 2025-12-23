`include "parameter.v"

module image_write #(
  parameter WIDTH = 768,
  parameter HEIGHT = 512,
  parameter BMP_HEADER_NUM = 54
)(
  input  HCLK,
  input  HRESETn,
  input  HSYNC,
  input  PREVIEW_MODE, 
  input  [7:0] DATA_R0, DATA_G0, DATA_B0,
  input  [7:0] DATA_R1, DATA_G1, DATA_B1,
  input        ctrl_done,
  output reg   Write_Done
);

reg [7:0] out_BMP [0:(WIDTH*HEIGHT*3)-1];
integer fd;
integer i, j;
integer pixel_count;
integer line_count;

localparam PREV_W = 100;
localparam PREV_H = 100;
localparam PREV_PADDING = 0; 
localparam PREV_SIZE = 54 + (PREV_W*3 + PREV_PADDING) * PREV_H;

localparam FULL_ROW_SIZE = ((WIDTH*3 + 3) / 4) * 4;
localparam FULL_PADDING  = FULL_ROW_SIZE - WIDTH*3;

reg trigger_save;

always @(posedge HCLK or negedge HRESETn) begin
  if (!HRESETn) begin
    pixel_count <= 0;
    line_count  <= 0;
    trigger_save <= 0;
  end else begin
    if (HSYNC) begin
       out_BMP[pixel_count]   <= DATA_B0;
       out_BMP[pixel_count+1] <= DATA_G0;
       out_BMP[pixel_count+2] <= DATA_R0;
       out_BMP[pixel_count+3] <= DATA_B1;
       out_BMP[pixel_count+4] <= DATA_G1;
       out_BMP[pixel_count+5] <= DATA_R1;
       pixel_count <= pixel_count + 6;
       
       if ((pixel_count + 6) % (WIDTH*3) == 0) line_count <= line_count + 1;
    end
    
    if (PREVIEW_MODE) begin
       if (line_count >= PREV_H && !Write_Done) trigger_save <= 1;
    end else begin
       if (ctrl_done && !Write_Done) trigger_save <= 1;
    end
  end
end

task write_header;
  input [31:0] w, h, fsize;
  input integer file_desc;
  reg [7:0] header [0:53];
  integer k;
  begin
      header[0]="B"; header[1]="M";
      header[2]=fsize[7:0]; header[3]=fsize[15:8]; header[4]=fsize[23:16]; header[5]=fsize[31:24];
      header[6]=0; header[7]=0; header[8]=0; header[9]=0;
      header[10]=54; header[11]=0; header[12]=0; header[13]=0;
      header[14]=40; header[15]=0; header[16]=0; header[17]=0;
      header[18]=w[7:0]; header[19]=w[15:8]; header[20]=0; header[21]=0;
      header[22]=h[7:0]; header[23]=h[15:8]; header[24]=h[23:16]; header[25]=h[31:24];
      header[26]=1; header[27]=0; header[28]=24; header[29]=0;
      header[30]=0; header[31]=0; header[32]=0; header[33]=0;
      header[34]=0; header[35]=0; header[36]=0; header[37]=0;
      header[38]=0; header[39]=0; header[40]=0; header[41]=0;
      header[42]=0; header[43]=0; header[44]=0; header[45]=0;
      header[46]=0; header[47]=0; header[48]=0; header[49]=0;
      header[50]=0; header[51]=0; header[52]=0; header[53]=0;
      for (k=0; k<54; k=k+1) $fwrite(file_desc, "%c", header[k]);
  end
endtask

always @(posedge HCLK or negedge HRESETn) begin
  if (!HRESETn) begin
     Write_Done <= 0;
  end else if (trigger_save && !Write_Done) begin
     
     if (PREVIEW_MODE) begin
         fd = $fopen("test_preview.bmp", "wb+");
         write_header(PREV_W, -PREV_H, PREV_SIZE, fd);
         
         for (i = 0; i < PREV_H; i = i + 1) begin
             for (j = 0; j < PREV_W*3; j = j + 1) begin
                 $fwrite(fd, "%c", out_BMP[i*WIDTH*3 + j]);
             end
             for (j = 0; j < PREV_PADDING; j = j + 1) $fwrite(fd, "%c", 0);
         end
         $display("-> Saved PREVIEW: test_preview.bmp (100x100)");

     end else begin
         fd = $fopen("output_full.bmp", "wb+");
         write_header(WIDTH, -HEIGHT, 54 + (WIDTH*3 + FULL_PADDING)*HEIGHT, fd);
         
         for (i = 0; i < HEIGHT; i = i + 1) begin
             for (j = 0; j < WIDTH*3; j = j + 1) begin
                 $fwrite(fd, "%c", out_BMP[i*WIDTH*3 + j]);
             end
             for (j = 0; j < FULL_PADDING; j = j + 1) $fwrite(fd, "%c", 0);
         end
         $display("-> Saved FULL IMAGE: output_full.bmp");
     end
     
     $fclose(fd);
     Write_Done <= 1;
  end
end
endmodule

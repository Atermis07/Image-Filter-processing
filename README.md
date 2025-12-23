First, run .v code 
then copy file .hex to filter_3\filter_3.sim\sim_1\behav\xsim
change the input you want .hex in parameter.v
Vivado Image Processing Simulation User Guide

Pipeline & Feedback Mode

This guide explains how to control the simulation in the Vivado Tcl Console.
The system supports running a single filter or multiple filters sequentially (Pipeline) using the feedback mechanism.

📋 1. Filter Control Codes (tcl_filter_sel)

When selecting a filter, you must use the correct decimal code.

Filter Name

Code (Decimal)

Description

Original

0

Bypass/No effect

Brightness

1

Adds constant value to brightness

Invert

2

Inverts colors (Negative)

Threshold

3

Black & White thresholding

Median

5

Noise reduction (removes salt & pepper noise)

Sobel

6

Edge detection

⚠️ IMPORTANT: Command Syntax

When setting values for tcl_filter_sel, you MUST specify the radix (number base) to ensure Vivado interprets the number correctly as Decimal.

Incorrect: add_force tcl_filter_sel 5 (May be interpreted as binary or hex depending on settings)

Correct: add_force tcl_filter_sel -radix dec 5

🚀 Workflow: Running a Pipeline (Median -> Sobel)

Follow these steps exactly in the Tcl Console to clean a noisy image and then detect its edges.

STEP 1: Run the First Filter (Median - Code 5)

Goal: Remove noise from the input image.

Reset the System:

add_force tcl_reset_n 0
run 100 ns
add_force tcl_reset_n 1


Select Filter (Median):

add_force tcl_filter_sel -radix dec 5


Select Full Mode (0) & Run:

add_force tcl_preview_mode 0
run 6 ms


Result: output_full.bmp is now the denoised image.

STEP 2: Trigger Feedback (Copy Output -> Input)

Goal: Move the processed result from the Output RAM back to the Input RAM for the next stage.

Enable Trigger:

add_force tcl_feedback_trigger 1
run 100 ns


Disable Trigger:

add_force tcl_feedback_trigger 0
run 100 ns


Check the console for the message: [FEEDBACK] -> Da cap nhat xong!

STEP 3: Run the Second Filter (Sobel - Code 6)

Goal: Detect edges on the clean image.

Reset the System Counters (CRITICAL):
Note: This resets pixel coordinates (row/col) to 0, but DOES NOT erase the image data in RAM.

add_force tcl_reset_n 0
run 100 ns
add_force tcl_reset_n 1


Select Filter (Sobel):

add_force tcl_filter_sel -radix dec 6


Run Simulation Again:

run 6 ms


Result: output_full.bmp is updated with the final Edge Detection result.

🛠 Troubleshooting

Error: "No such HDL object"

Make sure you have clicked Run Behavioral Simulation and the waveform window is open before typing commands.

The second filter looks wrong or black.

Did you forget to Reset (Step 3.1) after the feedback step? The simulation needs to restart the pixel counters from (0,0).

Did you use -radix dec? If you typed add_force tcl_filter_sel 5 without radix, it might have selected the wrong filter logic.

Where is my output file?

The output_full.bmp file is usually located in:
{Project_Folder}/{Project_Name}.sim/sim_1/behav/xsim/

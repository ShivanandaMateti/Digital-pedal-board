`timescale 1ns/1ps
module effects_regression;
reg clk=0, rst=1, valid=0, en=1;
reg signed [15:0] x=0;
wire signed [15:0] w,p,c,t,pu,pd,l,d,r,z;
distortion Z(clk,rst,en,valid,x,,z);
wah W(clk,rst,en,valid,x,,w);
phaser P(clk,rst,en,valid,x,,p);
chorus C(clk,rst,en,valid,x,,c);
tremolo T(clk,rst,en,valid,x,,t);
pitch_shift #(.MODE(1)) U(clk,rst,en,valid,x,,pu);
pitch_shift #(.MODE(2)) D(clk,rst,en,valid,x,,pd);
looper #(.MAX_LOOP_SAMPLES(44),.LOOP_MS(1)) L(clk,rst,en,valid,x,,l);
delay_echo #(.MAX_DELAY_SAMPLES(44),.DELAY_MS(1)) E(clk,rst,en,valid,x,,d);
delay_echo #(.MAX_DELAY_SAMPLES(44),.DELAY_MS(1),.FEEDBACK_Q15(16'hffff)) B(clk,rst,en,valid,x,,);
reverb R(clk,rst,en,valid,x,,r);
integer i, f, changes=0; reg old_pol=0;
initial begin
#1; clk=1; #1; clk=0; #1;
force W.lfo_phase=24'h400000; force P.lfo_phase=24'h400000; force C.lfo_phase=24'h400000;
#1; if (W.f_coeff !== 16'sd5900 || P.a_coeff !== 16'sd0 || C.total_delay != 350)
 $fatal(1,"Coefficient midpoint regression");
force W.lfo_phase=24'h7fffff; force P.lfo_phase=24'h7fffff; force C.lfo_phase=24'h7fffff;
#1; if (W.f_coeff !== 16'sd9999 || P.a_coeff !== 16'sd19998 || C.delay_q8 < 449*256)
 $fatal(1,"Coefficient endpoint regression");
x=10000; #1;
if (W.mixed_out != ((10000*13107)>>>15)+(($signed(W.sat_bp)*19660)>>>15))
 $fatal(1,"Wah mix precedence regression");
if (B.feedback_gain_32 != 28000) $fatal(1,"Feedback clamp regression");
release W.lfo_phase; release P.lfo_phase; release C.lfo_phase;
// Reset after artificial phase probes.
rst=0; #1; rst=1; #1; clk=1; #1; clk=0; #1; rst=0;
f=$fopen("samples.txt","w"); valid=1;
for(i=0;i<44100;i=i+1) begin
 x=$rtoi(1000.0*$sin(6.283185307179586*440.0*i/44100.0));
 #5; clk=1; #1;
 if(D.sub_polarity!=old_pol) changes=changes+1;
 old_pol=D.sub_polarity;
 $fdisplay(f,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",x,w,p,c,t,pu,pd,l,d,r,W.f_coeff,P.a_coeff,z);
 #4;clk=0;
end
$fclose(f);
if(changes < 438 || changes > 441) $fatal(1,"Octave down missed crossings");
// All modules must bypass even after effect state has been populated.
en=0;
for(i=0;i<20;i=i+1) begin
 x=(i%2) ? -32768+i : 32767-i;
 #5;clk=1;#1;
 if(w!==x || p!==x || c!==x || t!==x || pu!==x || pd!==x || l!==x || d!==x || r!==x || z!==x)
  $fatal(1,"Bypass mismatch");
 #4;clk=0;
end
$display("PASS: coefficient probes, feedback clamp, octave crossing detection, all-module bypass");
$finish;
end
endmodule

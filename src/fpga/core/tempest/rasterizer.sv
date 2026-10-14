`timescale 1ns / 1ps

// Pocket port: inputs are already in screen space (0..511 visible,
// values outside are clipped per pixel). OFFS keeps the internal
// arithmetic positive.
`define RAST_OFFS 14'sd1024

module rasterizer
  (
   input logic signed [12:0] startX,
   input logic signed [12:0] endX,
   input logic signed [12:0] startY,
   input logic signed [12:0] endY,
   input logic [3:0]         lineColor,
   input logic               clk,
   input logic               rst,
   input logic               readyIn,
   output logic [17:0]       addressOut,
   (* mark_debug = "true" *) output logic [12:0]       pixelX,
   (* mark_debug = "true" *) output logic [12:0]       pixelY,
   (* mark_debug = "true" *) output logic [3:0]        pixelColor,
   (* mark_debug = "true" *) output logic              goodPixel,
   (* mark_debug = "true" *) output logic              done,
   (* mark_debug = "true" *) output logic              rastReady
   );

  logic                      inc, xZone, bZone, yZone;
  logic                      xNeg, yNeg, cntNeg;
  logic                      loopEn;

  logic signed [13:0]        adjStartX, adjEndX;
  logic signed [13:0]        adjStartY, adjEndY;

  logic signed [13:0]        truncStartX, truncEndX; //EDIT: truncate if out of bounds
  logic signed [13:0]        truncStartY, truncEndY;//EDIT: truncate if out of bounds

  logic [13:0]               absDeltaX, absDeltaY, numerator, denominator, numeratorPrime, denominatorPrime;

  logic [13:0]               majCnt, minCnt;

  logic [13:0]               leftX, topY;

  logic                      goodTime, goodX, goodY;

  logic                      idleReady;

  logic                      pipe1;


  assign truncStartX = startX;
  assign truncEndX = endX;
  assign truncStartY = startY;
  assign truncEndY = endY;

  always_ff @(posedge clk)
    if (rst) begin
      pixelColor <= '0;
      adjStartX  <= '0;
      adjEndX    <= '0;
      adjStartY  <= '0;
      adjEndY    <= '0;
    end else if (idleReady) begin
      pixelColor <= lineColor;
      adjStartX  <= truncStartX + `RAST_OFFS;
      adjEndX    <= truncEndX   + `RAST_OFFS;
      adjStartY  <= truncStartY + `RAST_OFFS;
      adjEndY    <= truncEndY   + `RAST_OFFS;
    end

  absSubtractor #(14) xSub(.A(adjEndX), .B(adjStartX), .absDiff(absDeltaX));
  absSubtractor #(14) ySub(.A(adjEndY), .B(adjStartY), .absDiff(absDeltaY));

  m_comparator #(14) slopePicker(.A(absDeltaX), .B(absDeltaY), .AgtB(xZone), .AeqB(bZone), .AltB(yZone));

  assign xNeg = adjStartX < adjEndX;
  assign yNeg = adjStartY < adjEndY;
  //xor xorNeg(cntNeg, xNeg, yNeg);
  assign cntNeg = xNeg ^ yNeg;

  m_register #(14) numerBank(.Q(numerator), .D(numeratorPrime), .clk(clk), .clr(rst), .en(pipe1));
  m_register #(14) denomBank(.Q(denominator), .D(denominatorPrime), .clk(clk), .clr(rst), .en(pipe1));


  switchMux #(14) recipSwitch(.U(numeratorPrime), .V(denominatorPrime), .Sel(yZone), .A(absDeltaY), .B(absDeltaX));

  m_counter #(14) majorCounter(.Q(majCnt), .D(14'd0), .clk(clk), .clr(rst), .load(idleReady), .up(1'b1), .en(loopEn));
  m_counter #(14) minorCounter(.Q(minCnt), .D(14'd0), .clk(clk), .clr(rst), .load(idleReady), .up(~cntNeg), .en(inc));


  bresenhamCore rasterCore(.numerator(numerator[12:0]), .denominator(denominator[12:0]), .clk(clk), .rst(rst|idleReady), .en(loopEn), .inc(inc));

  rasterFSM rasterControl(.readyIn(readyIn), .denominator(denominator[12:0]), .majCnt(majCnt[12:0]), .clk(clk), .rst(rst), .loopEn(loopEn), .done(done), .good(goodTime), .rastReady(rastReady), .idleReady(idleReady), .pipe1(pipe1));


  m_mux2to1 #(14) leftXMux(.Y(leftX), .Sel((bZone|xZone) ? xNeg : yNeg), .I0(adjEndX), .I1(adjStartX));
  m_mux2to1 #(14) topYMux(.Y(topY), .Sel(yZone ? yNeg : xNeg), .I0(adjEndY), .I1(adjStartY));


  logic [13:0] pixX14, pixY14;
  assign pixX14 = leftX + ((bZone|xZone) ? majCnt : minCnt) - `RAST_OFFS;
  assign pixY14 = topY + (yZone ? majCnt : minCnt) - `RAST_OFFS;
  assign pixelX = pixX14[12:0];
  assign pixelY = pixY14[12:0];

  // 512 x 512 frame buffer: address = {y, x}
  assign addressOut = {pixY14[8:0], pixX14[8:0]};

  assign goodX = (pixX14[13:9] == 5'd0);
  assign goodY = (pixY14[13:9] == 5'd0);

  assign goodPixel = goodX & goodY & goodTime;

endmodule: rasterizer



module coordinateIndexer
  (input logic [9:0] x,
   input logic [8:0]   y,
   output logic [18:0] index
   );

   assign index = ({{9{1'b0}},{x}}) + ({{1'b0},{y},{9{1'b0}}}) + ({{3{1'b0}},{y},{7{1'b0}}});


endmodule: coordinateIndexer

module rasterFSM
  (input logic readyIn,
   input logic [12:0] denominator, majCnt,
   input logic        clk, rst,
   output logic       loopEn, good, done, rastReady, idleReady, pipe1
   );

   typedef enum       {IDLE, ITER, DONE, PIPE} state;

   (* mark_debug = "true" *) state current;
  state next;

   assign rastReady = (current == IDLE);

   always_ff @(posedge clk)
     begin
        if(rst)
          current <= IDLE;
        else
          current <= next;

     end


  always_comb begin
    next      = current;
    pipe1     = '1;
    done      = '0;
    loopEn    = '0;
    good      = '0;
    idleReady = '0;

    case(current)
      IDLE: begin
        if (readyIn) begin
          next      = PIPE;
          idleReady = '1;
        end else begin
          next      = IDLE;
          idleReady = '0;
        end
        done   = '0;
        loopEn = '0;
        good   = '0;
        pipe1  = '0;
      end
      PIPE: begin
        next      = ITER;
        pipe1     = '1;
        done      = '0;
        loopEn    = '0;
        good      = '0;
        idleReady = '0;
      end
      ITER: begin
        if(denominator == majCnt)begin
          next   = DONE;
          loopEn = '0;
          good   = '1;
        end else begin
          next      = ITER;
          loopEn    = '1;
          good      = '1;
          idleReady = '0;
        end

        done  = '0;
        pipe1 = '0;

      end
      DONE: begin
        next      = IDLE;

        done      = '1;
        loopEn    = '0;
        good      = '0;
        idleReady = '0;
        pipe1     = '0;

      end
    endcase // case (current)
  end





endmodule: rasterFSM


module switchMux
  #(parameter BUSWIDTH = 13)
   (output logic [BUSWIDTH-1:0] U, V,
    input logic [BUSWIDTH-1:0] A, B,
    input logic                Sel
    );


   m_mux2to1 #(BUSWIDTH) uMux(.Y(U), .I0(A), .I1(B), .Sel(Sel));
   m_mux2to1 #(BUSWIDTH) vMux(.Y(V), .I0(B), .I1(A), .Sel(Sel));



endmodule: switchMux

module absSubtractor
  #(parameter BUSWIDTH = 13)
   (input logic [BUSWIDTH-1:0] A, B,
    output logic [BUSWIDTH-1:0] absDiff
    );

   logic [BUSWIDTH-1:0]         negB, diff;


   negator #(BUSWIDTH) bNegator(.valIn(B), .valOut(negB));
   m_adder #(BUSWIDTH) subtraction(diff,, A, negB, 1'b0);
   absVal #(BUSWIDTH) magnitude(.valIn(diff), .valOut(absDiff));



endmodule: absSubtractor



module bresenhamCore
  (input logic [12:0] numerator, denominator,
   input logic  clk, rst, en,
   output logic inc
   );

   logic [12:0] errSum, errDiff, errCurr, absErr, subtrahend, negDenom;

   negator #(13) denomNegator(.valIn(denominator), .valOut(negDenom));


   m_register #(13) errBank(.Q(errCurr), .D(errDiff), .clr(rst), .clk(clk), .en(en));

   absVal #(13) errMagnitude(.valIn(errSum), .valOut(absErr));

   m_mux2to1 #(13) subSelect(.Y(subtrahend), .I0(13'd0), .I1(negDenom), .Sel(inc));

   m_comparator #(13) comp   (,, inc, absErr, {{1'b0}, {denominator[12:1]}});

   m_adder #(13) errAdder(errSum,, errCurr, numerator, 1'b0);

   m_adder #(13) errSubtract(errDiff,, errSum, subtrahend, 1'b0);



endmodule: bresenhamCore


module negator
  #(parameter BUSWIDTH = 13)
   (input logic [BUSWIDTH-1:0] valIn,
    output logic [BUSWIDTH-1:0] valOut
    );

   assign valOut = 1'b1 + ~valIn;



endmodule: negator


module absVal
  #(parameter BUSWIDTH = 13)
   (input logic [BUSWIDTH-1:0] valIn,
    output logic [BUSWIDTH-1:0] valOut
    );

   logic [BUSWIDTH-1:0]         valMid;


   always_comb
     begin
        if(valIn[BUSWIDTH-1])
          valMid = ~valIn;
        else
          valMid = valIn;

     end


   assign valOut = valMid + valIn[BUSWIDTH-1];



endmodule: absVal

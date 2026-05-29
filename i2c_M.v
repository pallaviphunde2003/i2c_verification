module i2c_master (
    input  wire        clk,
    input  wire        rd_wr,
    input  wire        start,
    input  wire        stop,
    input  wire        reset,
    input  wire [6:0]  address,
    input  wire [7:0]  din,
    inout  wire        SDA,
    output wire        SCL,
    output reg  [7:0]  dout
);

  localparam S0  = 4'd0,  S1  = 4'd1,  S2  = 4'd2,  S3  = 4'd3,
             S4  = 4'd4,  S5  = 4'd5,  S6  = 4'd6,  S7  = 4'd7,
             S8  = 4'd8,  S9  = 4'd9,  S11 = 4'd11, S12 = 4'd12,
             S13 = 4'd13, S14 = 4'd14;

  reg [3:0] state;
  reg [2:0] count;
  reg        scl_out, sda_out;
  reg        ack, mode;
  reg [7:0] tx_reg;

  assign SDA = (sda_out == 1'b0) ? 1'b0 : 1'bz;
  assign SCL = (scl_out == 1'b0) ? 1'b0 : 1'bz;

  always @(posedge clk) begin
    if (reset) begin
      count   <= 3'd0;
      state   <= S0;
      scl_out <= 1'b1;
      sda_out <= 1'b1;
      ack     <= 1'b0;
      mode    <= 1'b0;
      tx_reg  <= 8'd0;
      dout    <= 8'd0;
    end else begin
      case (state)
        S0: begin 
          scl_out <= 1'b1; 
          sda_out <= 1'b1; 
          count   <= 3'd0; 
          if(start) state <= S1; 
        end
        
        S1: begin 
          sda_out <= 1'b0; 
          mode    <= rd_wr; 
          tx_reg  <= {address, rd_wr}; 
          state   <= S2; 
        end
        
        S2: begin 
          scl_out <= 1'b0; 
          sda_out <= tx_reg[3'd7 - count]; // Explicit MSB indexing
          state   <= S3; 
        end
        
        S3: begin 
          scl_out <= 1'b1; 
          if(count == 3'd7) state <= S4; 
          else begin 
            count <= count + 1'b1; 
            state <= S2; 
          end 
        end
        
        S4: begin 
          scl_out <= 1'b0; 
          sda_out <= 1'b1; 
          count   <= 3'd0; 
          state   <= S5; 
        end
        
        S5: begin
          scl_out <= 1'b1;
          if(SDA == 1'b0) begin
            ack <= 1'b1;
            if(mode) begin state <= S8;  tx_reg <= 8'd0; end
            else     begin state <= S6;  tx_reg <= din;  end
          end else begin 
            ack   <= 1'b0; 
            state <= S0; 
          end
        end
        
        S6: begin
          scl_out <= 1'b0;
          if(stop && count == 3'd0) begin 
            sda_out <= 1'b0; 
            state   <= S13; 
          end else begin 
            sda_out <= tx_reg[3'd7 - count]; // Explicit MSB indexing
            state   <= S7; 
          end
        end
        
        S7: begin 
          scl_out <= 1'b1; 
          if(count == 3'd7) state <= S4; 
          else begin 
            count <= count + 1'b1; 
            state <= S6; 
          end 
        end
        
        S8: begin
          scl_out <= 1'b0; 
          sda_out <= 1'b1;
          if(stop) begin sda_out <= 1'b0; state <= S13; end
          else     state <= S9;
        end
        
        S9: begin 
          scl_out <= 1'b1; 
          tx_reg[3'd7 - count] <= SDA; // MSB indexing
          if(count == 3'd7) state <= S11; 
          else begin 
            count <= count + 1'b1; 
            state <= S8; 
          end 
        end
        
        S11: begin scl_out <= 1'b0; sda_out <= 1'b0; count <= 3'd0; state <= S12; end
        S12: begin scl_out <= 1'b1; dout <= tx_reg; state <= S8; end
        S13: begin scl_out <= 1'b1; state <= S14; end
        S14: begin sda_out <= 1'b1; state <= S0;  end
        default: state <= S0;
      endcase
    end
  end
endmodule

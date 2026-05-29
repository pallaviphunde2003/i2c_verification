
module i2c_slave (
    inout  wire        SDA,
    input  wire        SCL,
    input  wire        reset,
    input  wire [7:0]  din,       
    input  wire [6:0]  address,   
    output reg  [7:0]  dout       
);

  localparam S0 = 3'd0,  
             S1 = 3'd1,  
             S3 = 3'd3,  
             S4 = 3'd4,  
             S5 = 3'd5,  
             S6 = 3'd6,  
             S7 = 3'd7;  

  reg [2:0] state;
  reg [2:0] count;
  reg [7:0] tx_reg;
  reg       sda_out;
  reg       mode;       

  assign SDA = (sda_out == 1'b0) ? 1'b0 : 1'bz;

  reg sda_prev;
  always @(posedge SDA or negedge SDA) begin
    if (reset) sda_prev <= 1'b1;
    else       sda_prev <= SDA;
  end
  wire start_det = (~SDA &  sda_prev & SCL);
  wire stop_det  = ( SDA & ~sda_prev & SCL);

  always @(posedge SCL or posedge reset) begin
    if (reset) begin
      state   <= S0;
      sda_out <= 1'b1;
      count   <= 3'd0;
      tx_reg  <= 8'd0;
      dout    <= 8'd0;
      mode    <= 1'b0;
    end else if (start_det) begin
      state   <= S1;
      count   <= 3'd0;
      sda_out <= 1'b1;
    end else if (stop_det) begin
      state   <= S0;
      sda_out <= 1'b1;
    end else begin
      case (state)
        S0: begin
          sda_out <= 1'b1;
          count   <= 3'd0;
        end

        S1: begin
          tx_reg[3'd7 - count] <= SDA; // Handle bit indexing uniformly via explicit expression         
          if (count == 3'd7) begin
            if ({tx_reg[7:1], SDA} == address) begin // Include live SDA bit for immediate match
              sda_out <= 1'b0;            
              mode    <= SDA;             
              state   <= S3;
            end else begin
              sda_out <= 1'b1;            
              state   <= S0;
            end
            count <= 3'd0;
          end else begin
            count <= count + 1'b1;
          end
        end

        S3: begin
          count   <= 3'd0;
          if (mode == 1'b1) begin         
            tx_reg  <= din;
            sda_out <= din[7];            
            state   <= S4;
          end else begin                  
            sda_out <= 1'b1;             
            state   <= S5;
          end
        end

        S4: begin
          state <= S5;
        end

        S5: begin
          if (mode == 1'b1) begin         
            if (count == 3'd7) begin
              sda_out <= 1'b1;
              state   <= S6;
              count   <= 3'd0;
            end else begin
              sda_out <= tx_reg[3'd7 - (count + 1'b1)];
              count   <= count + 1'b1;
              state   <= S5;              
            end
          end else begin                  
            tx_reg[3'd7 - count] <= SDA;        
            if (count == 3'd7) begin
              sda_out <= 1'b0;            
              dout    <= {tx_reg[7:1], SDA}; 
              state   <= S7;
              count   <= 3'd0;
            end else begin
              count <= count + 1'b1;
            end
          end
        end

        S6: begin
          if (SDA == 1'b0) begin          
            tx_reg  <= din;
            sda_out <= din[7];            
            count   <= 3'd0;
            state   <= S4;
          end else begin                  
            sda_out <= 1'b1;
            state   <= S0;
          end
        end

        S7: begin
          sda_out <= 1'b1;                
          count   <= 3'd0;
          state   <= S5;                  
        end

        default: state <= S0;
      endcase
    end
  end
endmodule

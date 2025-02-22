`timescale 1ns / 1ps
 
 
///////////////////////// LCR is used in TX  

/*
clk
rst
baud_pulse
pen: parity enable
threshold: threshold trigger 
stb: stop bit
sticky_parity
eps
set_break
din
wls: data witdth
pop
shift_reg_empty
tx
*/
  
module uart_tx_top(
  input clk, rst, baud_pulse, pen, threshold, stb, sticky_parity, eps, set_break,
  input [7:0] din,
  input [1:0] wls,
  output reg pop, shift_reg_empty, tx
);
  
  
  typedef enum logic [1:0] {idle = 0, start = 1 , send = 2 , parity = 3} state_type;
  state_type state = idle;   
    
  reg [7:0] shift_reg;
  reg tx_data;
  reg d_parity;
  reg [2:0] bitcnt = 0;
  reg [4:0] count = 5'd15;
  reg parity_out;
 
 
  always@(posedge clk, posedge rst) begin
    if(rst) begin
      state  <= idle;
      count  <= 5'd15;
      bitcnt <= 0;
      ///////////////
      shift_reg   <= 8'bxxxxxxxx;
      pop        <= 1'b0;
      shift_reg_empty <= 1'b0; // not empty
      tx_data    <= 1'b1; //idle value
    end
    else if(baud_pulse) begin
      case(state)
        ////////////// idle state
        idle: begin
          if(threshold == 1'b0) begin ///csr.lsr.threshold  
            if(count != 0) begin
              count <= count - 1;
              state <= idle;
            end
            else begin
              count <= 5'd15;
              state <= start;
              bitcnt  <= {1'b1,wls};
              /////////////////////////
              pop         <= 1'b1;  ///read tx fifo
              shift_reg    <= din;   /// store fifo data in shift reg
              shift_reg_empty  <= 1'b0;
              /////////////////////////////////                       
              tx_data <= 1'b0; ///start bit 
            end
          end
        end
          
        /////////////start state
        start: begin
          /////////////// calculate parity
          case(wls)
            2'b00: d_parity <= ^din[4:0];
            2'b01: d_parity <= ^din[5:0];
            2'b10: d_parity <= ^din[6:0];
            2'b11: d_parity <= ^din[7:0];             
          endcase
                  
          if( count != 0) begin
            count <= count - 1;
            state <= start;
          end
          else begin
            count  <= 5'd15;
            state  <= send;
            /////////////////////////////
            tx_data    <= shift_reg[0]; 
            shift_reg   <= shift_reg >> 1; 
            ////////////////////////
            pop        <= 1'b0;
          end
        end

        ///////////////// send state
        send: begin
          case({sticky_parity, eps})
            2'b00: parity_out <= ~d_parity;
            2'b01: parity_out <= d_parity;
            2'b10: parity_out <= 1'b1;
            2'b11: parity_out <= 1'b0;
          endcase

          if(bitcnt != 0)
            begin
              if(count != 0) begin
                count <= count - 1;
                state <= send;  
              end
              else begin
                count <= 5'd15;
                bitcnt <= bitcnt - 1;
                tx_data    <= shift_reg[0]; 
                shift_reg   <= shift_reg >> 1;
                state <= send;
              end
            end
          else begin
            ///////////////////////////
            if(count != 0) begin
              count <= count - 1;
              state <= send;  
            end
            else begin
              count <= 5'd15;
              shift_reg_empty <= 1'b1;

              if(pen == 1'b1) begin
                state <= parity;
                count <= 5'd15;
                tx_data <= parity_out;
              end  
              ////////////////////////
              else begin
                tx_data <= 1'b1;
                count   <= (stb == 1'b0 )? 5'd15 :(wls == 2'b00) ? 5'd23 : 5'd31;
                state   <= idle;
              end  
            end
          end/// else of bitcnt loop
        end

        parity: begin
          if(count != 0)
            begin
            count <= count - 1;
            state <= parity;
            end
          else
            begin
            tx_data <= 1'b1;
            count   <= (stb == 1'b0 )? 5'd15 :(wls == 2'b00) ? 5'd17 : 5'd31;
            state <= idle;
            end
        end 
            
        default: ;
      endcase   
    end
  end
 
     
////////////////////////////////////////////////////// 
  always@(posedge clk, posedge rst) begin
    if(rst)
      tx <= 1'b1;
    else
      tx <= tx_data & ~set_break;
  end    

endmodule
// ============================================================================
// FIXED UART
// Only minimal corrections applied to your ORIGINAL architecture
// ============================================================================

module riscv32i_uart #(

  parameter CLOCK_FREQUENCY = 50000000,
  parameter UART_BAUD_RATE  = 9600

)(

  input   wire          clock,
  input   wire          reset,

  input  wire   [4:0 ]  rw_address,
  output reg    [31:0]  read_data,

  input  wire           read_request,
  output reg            read_response,

  input  wire   [7:0]   write_data,
  input  wire           write_request,
  output reg            write_response,

  input   wire          uart_rx,
  output  wire          uart_tx,

  output  reg           uart_irq,
  input   wire          uart_irq_response

);

  localparam CYCLES_PER_BAUD = CLOCK_FREQUENCY / UART_BAUD_RATE;

  // ==========================================================================
  // REGISTER MAP
  // ==========================================================================
  localparam REG_WDATA    = 5'h00;
  localparam REG_RDATA    = 5'h04;
  localparam REG_READY    = 5'h08;
  localparam REG_RXSTATUS = 5'h0c;

  // ==========================================================================
  // TX REGISTERS
  // ==========================================================================
  reg [31:0] tx_cycle_counter = 0;
  reg [3:0]  tx_bit_counter   = 0;
  reg [9:0]  tx_register      = 10'b1111111111;

  // ==========================================================================
  // RX REGISTERS
  // ==========================================================================
  reg [31:0] rx_cycle_counter = 0;
  reg [3:0]  rx_bit_counter   = 0;

  reg [7:0]  rx_register      = 0;
  reg [7:0]  rx_data          = 0;

  reg         rx_active       = 0;
  reg         rx_stop_wait    = 0;

  // ==========================================================================
  // RESET
  // ==========================================================================
  reg reset_reg = 0;

  always @(posedge clock)
    reset_reg <= reset;

  wire reset_internal = reset | reset_reg;

  // ==========================================================================
  // UART TX
  //
  reg write_request_d;
reg read_request_d;

always @(posedge clock) begin

  write_request_d <= write_request;
  read_request_d  <= read_request;

  write_response <= write_request_d;
  read_response  <= read_request_d;

end
  assign uart_tx = tx_register[0];

  always @(posedge clock) begin

    if (reset_internal) begin

      tx_cycle_counter <= 0;
      tx_bit_counter   <= 0;
      tx_register      <= 10'b1111111111;

    end

    // ------------------------------------------------------------------------
    // LOAD TX DATA
    // ------------------------------------------------------------------------
    else if (tx_bit_counter == 0 &&
             rw_address == REG_WDATA &&
             write_request == 1'b1) begin

      tx_cycle_counter <= 0;

      // stop + data + start
      tx_register <= {1'b1, write_data[7:0], 1'b0};

      tx_bit_counter <= 10;

    end

    // ------------------------------------------------------------------------
    // TRANSMIT
    // ------------------------------------------------------------------------
    else if (tx_bit_counter > 0) begin

      // FIXED OFF-BY-ONE
      if (tx_cycle_counter < CYCLES_PER_BAUD - 1) begin

        tx_cycle_counter <= tx_cycle_counter + 1;

      end
      else begin

        tx_cycle_counter <= 0;

        tx_register <= {1'b1, tx_register[9:1]};

        tx_bit_counter <= tx_bit_counter - 1;

      end
    end
  end

  // ==========================================================================
  // UART RX
  // ==========================================================================
  always @(posedge clock) begin

    if (reset_internal) begin

      rx_cycle_counter <= 0;
      rx_bit_counter   <= 0;

      rx_register <= 0;
      rx_data     <= 0;

      rx_active    <= 0;
      rx_stop_wait <= 0;

      uart_irq <= 0;

    end

    else begin

      // ----------------------------------------------------------------------
      // CLEAR IRQ
      // ----------------------------------------------------------------------
      if (uart_irq == 1'b1) begin

        if (uart_irq_response ||
           (rw_address == REG_RDATA && read_request)) begin

          uart_irq <= 0;

        end
      end

      // ----------------------------------------------------------------------
      // WAIT FOR START BIT
      // ----------------------------------------------------------------------
      if (!rx_active && !rx_stop_wait) begin

        if (uart_rx == 1'b0) begin

          // HALF BIT ALIGN
          if (rx_cycle_counter < (CYCLES_PER_BAUD/2)-1) begin

            rx_cycle_counter <= rx_cycle_counter + 1;

          end
          else begin

            rx_cycle_counter <= 0;

            rx_bit_counter <= 8;

            rx_active <= 1'b1;

          end
        end
        else begin

          rx_cycle_counter <= 0;

        end
      end

      // ----------------------------------------------------------------------
      // RECEIVE DATA
      // ----------------------------------------------------------------------
      else if (rx_active) begin

        // FIXED OFF-BY-ONE
        if (rx_cycle_counter < CYCLES_PER_BAUD - 1) begin

          rx_cycle_counter <= rx_cycle_counter + 1;

        end
        else begin

          rx_cycle_counter <= 0;

          // ORIGINAL SHIFT (CORRECT)
          rx_register <= {uart_rx, rx_register[7:1]};

          // ================================================================
          // LAST BIT
          // ================================================================
          if (rx_bit_counter == 1) begin

            rx_bit_counter <= 0;

            rx_active <= 0;

            rx_stop_wait <= 1'b1;

            rx_data <= {uart_rx, rx_register[7:1]};

          end
          else begin

            rx_bit_counter <= rx_bit_counter - 1;

          end
        end
      end

      // ----------------------------------------------------------------------
      // STOP BIT WAIT
      // ----------------------------------------------------------------------
      else if (rx_stop_wait) begin

        if (rx_cycle_counter < CYCLES_PER_BAUD - 1) begin

          rx_cycle_counter <= rx_cycle_counter + 1;

        end
        else begin

          rx_cycle_counter <= 0;

          rx_stop_wait <= 0;

          // VALID STOP BIT
          if (uart_rx == 1'b1) begin

            uart_irq <= 1'b1;

          end
        end
      end
    end
  end

  // ==========================================================================
  // BUS RESPONSE
  // ==========================================================================
  always @(posedge clock) begin

    if (reset_internal) begin

      read_response  <= 0;
      write_response <= 0;

    end
    else begin

      read_response  <= read_request;
      write_response <= write_request;

    end
  end

  // ==========================================================================
  // READ DATA
  // ==========================================================================
  always @(posedge clock) begin

    if (reset_internal) begin

      read_data <= 32'h00000000;

    end
    else begin

      if (rw_address == REG_RDATA && read_request)

        read_data <= {24'b0, rx_data};

      else if (rw_address == REG_READY && read_request)

        read_data <= {31'b0, tx_bit_counter == 0};

      else if (rw_address == REG_RXSTATUS && read_request)

        read_data <= {31'b0, uart_irq};

      else

        read_data <= 32'h00000000;

    end
  end

endmodule

`timescale 1ns/1ps

module tb_uart;

  // ==========================================================
  // CLOCK + RESET
  // ==========================================================
  reg clock;
  reg reset;

  initial begin
    clock = 0;
    forever #10 clock = ~clock;
  end

  // ==========================================================
  // BUS SIGNALS
  // ==========================================================
  reg  [4:0] rw_address;
  reg        read_request;

  reg  [7:0] write_data;
  reg        write_request;

  wire [31:0] read_data;
  wire        read_response;
  wire        write_response;

  // ==========================================================
  // UART SIGNALS
  // ==========================================================
  wire uart_tx;
  wire uart_rx;

  wire uart_irq;

  // LOOPBACK
  assign uart_rx = uart_tx;

  // ==========================================================
  // DUT
  // ==========================================================
  riscv32i_uart #(
    .CLOCK_FREQUENCY(20),
    .UART_BAUD_RATE(2)
  ) dut (

    .clock(clock),
    .reset(reset),

    .rw_address(rw_address),
    .read_data(read_data),

    .read_request(read_request),
    .read_response(read_response),

    .write_data(write_data),
    .write_request(write_request),
    .write_response(write_response),

    .uart_rx(uart_rx),
    .uart_tx(uart_tx),

    .uart_irq(uart_irq),
    .uart_irq_response(1'b0)
  );

  // ==========================================================
  // VCD DUMP
  // ==========================================================
  initial begin
    $dumpfile("riscv32i_uart.vcd");
    $dumpvars(0, tb_uart);
  end

  // ==========================================================
  // MONITOR
  // ==========================================================
  initial begin
    $monitor(
      "TIME=%0t | TX=%b RX=%b | TX_CNT=%0d RX_CNT=%0d | IRQ=%b | READ_DATA=%h",
      $time,
      uart_tx,
      uart_rx,
      dut.tx_bit_counter,
      dut.rx_bit_counter,
      uart_irq,
      read_data
    );
  end

  // ==========================================================
  // TEST
  // ==========================================================
  initial begin

    // --------------------------------------------------------
    // INIT
    // --------------------------------------------------------
    reset         = 1;

    rw_address    = 0;
    read_request  = 0;

    write_data    = 0;
    write_request = 0;

    // --------------------------------------------------------
    // RESET
    // --------------------------------------------------------
    #200;
    reset = 0;

    $display("\nRESET RELEASED\n");

    // --------------------------------------------------------
    // WAIT FEW CLOCKS
    // --------------------------------------------------------
    repeat(5) @(posedge clock);

    // --------------------------------------------------------
    // WRITE BYTE
    // --------------------------------------------------------
    $display("\nSENDING BYTE = A5\n");

    @(negedge clock);

    rw_address    = 5'h00;
    write_data    = 8'hA5;
    write_request = 1'b1;

    @(negedge clock);

    write_request = 1'b0;

    // --------------------------------------------------------
    // WAIT IRQ
    // --------------------------------------------------------
    wait(uart_irq == 1'b1);

    $display("\nBYTE RECEIVED SUCCESSFULLY\n");

    // --------------------------------------------------------
    // READ RECEIVED BYTE
    // --------------------------------------------------------
    @(negedge clock);

    rw_address   = 5'h04;
    read_request = 1'b1;

    @(posedge clock);

    $display("READ DATA = %h", read_data);

    // KEEP REQUEST HIGH FOR VISIBILITY
    repeat(3) @(posedge clock);

    read_request = 1'b0;

    // --------------------------------------------------------
    // FINISH
    // --------------------------------------------------------
    #500;

    $finish;

  end

endmodule
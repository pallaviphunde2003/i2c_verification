//interface

interface master_interface (input logic clk);
  logic [7:0] din, dout;
  logic [6:0] address;
  logic reset, start, stop, mode;
endinterface

interface slave_interface (input logic clk);
  logic [7:0] din, dout;
  logic [6:0] address;
  logic reset;
endinterface

class packet;
  rand bit [6:0] address;
  rand bit [7:0] data;
  rand bit       mode;
  bit            error;

  constraint match_slave { address == 7'h5A; }

  function void display(string name = "PACKET");
    $display("[%0s] @ %0t : addr=7'h%0h  data=8'h%0h  mode=%0s",
             name, $time, address, data, mode ? "READ" : "WRITE");
  endfunction
endclass

class sync_info;
  bit [6:0] address;
  bit [7:0] data;
  bit       mode;
endclass

// MASTER DRIVER

class master_driver;
  virtual master_interface mintf;
  mailbox #(logic [7:0])   mdrv2sb;
  mailbox #(sync_info)     addr_sync;
  packet                   pkt;

  function new(virtual master_interface mintf,
               mailbox #(logic [7:0])   mdrv2sb,
               mailbox #(sync_info)     addr_sync);
    this.mintf     = mintf;
    this.mdrv2sb   = mdrv2sb;
    this.addr_sync = addr_sync;
    this.pkt       = new();
  endfunction

  task run(int no_of_bytes, bit run_mode);
    $display("[MASTER DRV] Starting %0d-byte transfer, mode=%0s",
             no_of_bytes, run_mode ? "READ" : "WRITE");

    repeat (no_of_bytes) begin
      sync_info si = new();

      if (!pkt.randomize()) $error("[MASTER DRV] Randomization failed!");
      pkt.mode = run_mode;

      si.address = pkt.address;
      si.mode    = pkt.mode;
      si.data    = pkt.data;
      addr_sync.put(si);

      @(posedge mintf.clk);
      mintf.address <= pkt.address;
      mintf.mode    <= pkt.mode;

      if (pkt.mode == 1'b0) begin        
        mintf.din <= pkt.data;
        mdrv2sb.put(pkt.data);
      end

      mintf.start <= 1'b1;
      @(posedge mintf.clk);
      mintf.start <= 1'b0;

      @(posedge mintf.clk);
      while (top.master.state == 4'd0) @(posedge mintf.clk);

      if (pkt.mode == 1'b1) begin

        while (top.master.state != 4'd12) @(posedge mintf.clk);
        @(posedge mintf.clk);            
        mdrv2sb.put(mintf.dout);
      end

  
      while (top.master.state != 4'd0) @(posedge mintf.clk);

      mintf.stop <= 1'b1;
      repeat(2) @(posedge mintf.clk);
      mintf.stop <= 1'b0;

      repeat(20) @(posedge mintf.clk);
    end
  endtask
endclass


// SLAVE DRIVER

class slave_driver;
  virtual slave_interface  sintf;
  mailbox #(logic [7:0])   sdrv2sb;
  mailbox #(sync_info)     addr_sync;

  function new(virtual slave_interface  sintf,
               mailbox #(logic [7:0])   sdrv2sb,
               mailbox #(sync_info)     addr_sync);
    this.sintf     = sintf;
    this.sdrv2sb   = sdrv2sb;
    this.addr_sync = addr_sync;
  endfunction

  task run(int no_of_bytes, bit run_mode);
    $display("[SLAVE DRV]  Starting %0d-byte transfer, mode=%0s",
             no_of_bytes, run_mode ? "READ" : "WRITE");

    repeat (no_of_bytes) begin
      sync_info si;
      addr_sync.get(si);

      sintf.address = si.address;

      if (run_mode == 1'b1) begin        
        sintf.din = si.data;
        sdrv2sb.put(si.data);            
      end

      while (top.master.state == 4'd0) @(posedge sintf.clk);
      while (top.master.state != 4'd0) @(posedge sintf.clk);

      if (run_mode == 1'b0) begin       
        sdrv2sb.put(si.data);
      end

      repeat(20) @(posedge sintf.clk);
    end
  endtask
endclass

// SCOREBOARD

class scoreboard;
  logic [7:0]            mpkt, spkt;
  mailbox #(logic [7:0]) mdrv2sb, sdrv2sb;
  int                    errors = 0;

  function new(mailbox #(logic [7:0]) mdrv2sb,
               mailbox #(logic [7:0]) sdrv2sb);
    this.mdrv2sb = mdrv2sb;
    this.sdrv2sb = sdrv2sb;
  endfunction

  task run(int no_of_bytes);
    $display("[SCOREBOARD] Verification active");
    repeat (no_of_bytes) begin
      mdrv2sb.get(mpkt);
      sdrv2sb.get(spkt);
      $display("[SCOREBOARD] Master=8'h%0h  Slave=8'h%0h  %0s",
               mpkt, spkt, (mpkt === spkt) ? "PASS" : "FAIL");
      if (mpkt !== spkt) errors++;
      $display("----------------------------------------------------------------------");
    end
    $display("[SCOREBOARD] Complete — %0d mismatch error(s)", errors);
  endtask
endclass


// ENVIRONMENT

class environment;
  master_driver            mdrv;
  slave_driver             sdrv;
  scoreboard               sb;
  virtual master_interface mintf;
  virtual slave_interface  sintf;
  mailbox #(logic [7:0])   mdrv2sb, sdrv2sb;
  mailbox #(sync_info)     addr_sync;

  function new(virtual master_interface mintf,
               virtual slave_interface  sintf);
    this.mintf = mintf;
    this.sintf = sintf;
  endfunction

  function void build();
    $display("[ENV] Building components...");
    mdrv2sb   = new();
    sdrv2sb   = new();
    addr_sync = new();
    mdrv      = new(mintf, mdrv2sb, addr_sync);
    sdrv      = new(sintf, sdrv2sb, addr_sync);
    sb        = new(mdrv2sb, sdrv2sb);
  endfunction

  task reset();
    $display("[ENV] Reset...");
    mintf.start = 1'b0;
    mintf.stop  = 1'b0;
    @(posedge mintf.clk);
    mintf.reset = 1'b1;
    sintf.reset = 1'b1;
    repeat(4) @(posedge mintf.clk);
    mintf.reset = 1'b0;
    sintf.reset = 1'b0;
    repeat(5) @(posedge mintf.clk);
    $display("[ENV] Reset complete.");
  endtask

  task run_test(int n, bit mode);
    $display("[ENV] Running test...");
    fork
      mdrv.run(n, mode);
      sdrv.run(n, mode);
      sb.run(n);
    join
  endtask
endclass

// TOP MODULE

module top;
  reg clk = 0;
  always #40 clk = ~clk;

  wire SDA, SCL;
  pullup(SDA);
  pullup(SCL);

  master_interface mintf(clk);
  slave_interface  sintf(clk);

  i2c_master master (
    .clk    (clk),
    .rd_wr  (mintf.mode),
    .start  (mintf.start),
    .stop   (mintf.stop),
    .reset  (mintf.reset),
    .address(mintf.address),
    .din    (mintf.din),
    .SDA    (SDA),
    .SCL    (SCL),
    .dout   (mintf.dout)
  );

  i2c_slave slave (
    .SDA    (SDA),
    .SCL    (SCL),
    .reset  (sintf.reset),
    .din    (sintf.din),
    .address(sintf.address),
    .dout   (sintf.dout)
  );

  environment env;

  initial begin
    env = new(mintf, sintf);
    env.build();

    $display("\n========== TEST 1 : WRITE (Master to Slave) ==========");
    env.reset();
    #200;
    env.run_test(5, 1'b0);

    #1000;

    $display("\n========== TEST 2 : READ  (Slave to Master) ==========");
    env.reset();
    #200;
    env.run_test(5, 1'b1);

    #5000;
    $display("\n[TB] Done.");
    if (env.sb.errors == 0) $display(">>> All tests passed SUCCESSFULLY! <<<");
    else                    $display(">>> TEST BENCH FAILED WITH %0d ERRORS <<<", env.sb.errors);
    $finish;
  end

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, top);
  end
endmodule

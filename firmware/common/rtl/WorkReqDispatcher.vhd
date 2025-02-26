-------------------------------------------------------------------------------
-- Title      : WorkReqDispatcher
-- Project    : 
-------------------------------------------------------------------------------
-- File       : WorkReqDispatcher.vhd
-- Author     : Filippo Marini  <filippo.marini@pd.infn.it>
-- Company    : INFN Padova
-- Created    : 2024-08-01
-- Last update: 2025-02-26
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2024 INFN Padova
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2024-08-01  1.0      fmarini Created
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.AxiLitePkg.all;
use surf.RocePkg.all;

entity WorkReqDispatcher is

   generic (
      TPD_G                   : time                  := 1 ns;
      RST_ASYNC_G             : boolean               := false;
      DISPATCH_COUNTER_BITS_G : natural range 0 to 31 := 24
      );
   port (
      RoceClk          : in  std_logic;
      RoceRst          : in  std_logic;
      -- Roce Work Req
      workReqMaster    : out RoceWorkReqMasterType;
      workReqSlave     : in  RoceWorkReqSlaveType;
      -- Starting flag
      startingDispatch : out sl;
      -- Axi-Lite Registers
      axilReadMaster   : in  AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
      axilReadSlave    : out AxiLiteReadSlaveType;
      axilWriteMaster  : in  AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
      axilWriteSlave   : out AxiLiteWriteSlaveType
      );
end entity WorkReqDispatcher;

architecture rtl of WorkReqDispatcher is

   type AxilRegType is record
      startDispatching : sl;
      dispatchCounter  : slv(DISPATCH_COUNTER_BITS_G-1 downto 0);
      len              : slv(31 downto 0);
      rKey             : slv(31 downto 0);
      lKey             : slv(31 downto 0);
      sQpn             : slv(23 downto 0);
      dQpn             : slv(24 downto 0);
      rAddr            : slv(63 downto 0);
      axilReadSlave    : AxiLiteReadSlaveType;
      axilWriteSlave   : AxiLiteWriteSlaveType;
   end record AxilRegType;

   constant AXIL_REG_INIT_C : AxilRegType := (
      startDispatching => '0',
      dispatchCounter  => (others => '0'),
      len              => (others => '0'),
      rKey             => (others => '0'),
      lKey             => (others => '0'),
      sQpn             => (others => '0'),
      dQpn             => (others => '0'),
      rAddr            => (others => '0'),
      axilReadSlave    => AXI_LITE_READ_SLAVE_INIT_C,
      axilWriteSlave   => AXI_LITE_WRITE_SLAVE_INIT_C
      );

   signal regR   : AxilRegType := AXIL_REG_INIT_C;
   signal regRin : AxilRegType;

   type DispStateType is (st0_idle, st1_sending);

   type DispRegType is record
      state    : DispStateType;
      count    : slv(DISPATCH_COUNTER_BITS_G-1 downto 0);
      txMaster : RoceWorkReqMasterType;
   end record DispRegType;

   constant DISP_REG_INIT_C : DispRegType := (
      state    => st0_idle,
      count    => (others => '0'),
      txMaster => ROCE_WORK_REQ_MASTER_INIT_C
      );

   signal dispR   : DispRegType := DISP_REG_INIT_C;
   signal dispRin : DispRegType;

   signal startDispatching : sl;

begin  -- architecture rtl

   -----------------------------------------------------------------------------
   -- Axi-Lite Regs
   -----------------------------------------------------------------------------
   regComb : process (axilReadMaster, axilWriteMaster, regR) is
      variable v      : AxilRegType;
      variable regCon : AxiLiteEndPointType;
   begin  -- process regComb

      v := regR;

      -- Determine the transaction type
      axiSlaveWaitTxn(regCon, axilWriteMaster, axilReadMaster, v.axilWriteSlave, v.axilReadSlave);

      -- Gen registers
      axiSlaveRegister (regCon, x"F00", 0, v.startDispatching);
      axiSlaveRegister (regCon, x"F00", 1, v.dispatchCounter);
      axiSlaveRegister (regCon, x"F04", 0, v.len);
      axiSlaveRegister (regCon, x"F08", 0, v.rKey);
      axiSlaveRegister (regCon, x"F0C", 0, v.lKey);
      axiSlaveRegister (regCon, x"F10", 0, v.sQpn);
      axiSlaveRegister (regCon, x"F14", 0, v.dQpn);
      axiSlaveRegister (regCon, x"F18", 0, v.rAddr);

      -- Closeout the transaction
      axiSlaveDefault(regCon, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

      -- Outputs
      axilWriteSlave <= regR.axilWriteSlave;
      axilReadSlave  <= regR.axilReadSlave;

      -- Register update
      regRin <= v;

   end process regComb;

   regSeq : process (RoceClk, RoceRst) is
   begin
      if (RST_ASYNC_G) and (RoceRst = '1') then
         regR <= AXIL_REG_INIT_C after TPD_G;
      elsif (rising_edge(RoceClk)) then
         if (RST_ASYNC_G = false) and (RoceRst = '1') then
            regR <= AXIL_REG_INIT_C after TPD_G;
         else
            regR <= regRin after TPD_G;
         end if;
      end if;
   end process regSeq;

   -- Get rising_edge
   SynchronizerEdge_1 : entity surf.SynchronizerEdge
      generic map (
         TPD_G         => TPD_G,
         BYPASS_SYNC_G => true
         )
      port map (
         clk        => RoceClk,
         dataIn     => regR.startDispatching,
         risingEdge => startDispatching
         );

   startingDispatch <= startDispatching;

   -----------------------------------------------------------------------------
   -- Dispatcher
   -----------------------------------------------------------------------------
   dispComb : process (dispR, regR, startDispatching,
                       workReqSlave) is
      variable v         : dispRegType;
      variable idPadding : slv(63 downto DISPATCH_COUNTER_BITS_G) := (others => '0');
   begin  -- process dispComb

      -- Latch the current value
      v := dispR;

      -- Choose ready source and clear valid
      if workReqSlave.ready = '1' then
         v.txMaster.valid := '0';
      end if;

      -- FSM
      case dispR.state is
         -------------------------------------------------------------------------
         when st0_idle =>
            if startDispatching = '1' then
               v.state := st1_sending;
            end if;
         -----------------------------------------------------------------------
         when st1_sending =>
            if v.txMaster.valid = '0' then
               v.txMaster.id        := idPadding & dispR.count + 1;
               v.txMaster.opCode    := (others => '0');
               v.txMaster.flags     := "00010";  -- 2
               v.txMaster.rAddr     := regR.rAddr + (dispR.count * regR.len);
               v.txMaster.rKey      := regR.rKey;
               v.txMaster.len       := regR.len;
               v.txMaster.lAddr     := (others => '0');
               v.txMaster.lKey      := regR.lKey;
               v.txMaster.sQpn      := regR.sQpn;
               v.txMaster.solicited := '0';
               v.txMaster.comp      := (others => '0');
               v.txMaster.swap      := (others => '0');
               v.txMaster.immDt     := (others => '0');
               v.txMaster.rKeyToInv := (others => '0');
               v.txMaster.srqn      := (others => '0');
               v.txMaster.dQpn      := (others => '0');
               v.txMaster.qKey      := (others => '0');
               v.txMaster.valid     := '1';
               if dispR.count < regR.dispatchCounter - 1 then
                  v.count := v.count + 1;
                  v.state := st1_sending;
               else
                  v.count := (others => '0');
                  v.state := st0_idle;
               end if;
            end if;
         -----------------------------------------------------------------------
         when others =>
            v := DISP_REG_INIT_C;
      end case;

      workReqMaster <= dispR.txMaster;

      dispRin <= v;

   end process dispComb;

   dispSeq : process (RoceClk, RoceRst) is
   begin
      if (RST_ASYNC_G) and (RoceRst = '1') then
         dispR <= DISP_REG_INIT_C after TPD_G;
      elsif (rising_edge(RoceClk)) then
         if (RST_ASYNC_G = false) and (RoceRst = '1') then
            dispR <= DISP_REG_INIT_C after TPD_G;
         else
            dispR <= dispRin after TPD_G;
         end if;
      end if;
   end process dispSeq;

end architecture rtl;

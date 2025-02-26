-------------------------------------------------------------------------------
-- Title      : WorkCompChecker
-- Project    : 
-------------------------------------------------------------------------------
-- File       : WorkCompChecker.vhd
-- Author     : Filippo Marini  <filippo.marini@pd.infn.it>
-- Company    : INFN Padova
-- Created    : 2024-08-02
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
-- 2024-08-02  1.0      fmarini Created
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_misc.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;
use surf.RocePkg.all;

entity WorkCompChecker is
   generic (
      TPD_G                   : time                  := 1 ns;
      RST_ASYNC_G             : boolean               := false;
      DISPATCH_COUNTER_BITS_G : natural range 0 to 31 := 24
      );
   port (
      RoceClk          : in  sl;
      RoceRst          : in  sl;
      WorkCompMaster   : in  RoceWorkCompMasterType;
      WorkCompSlave    : out RoceWorkCompSlaveType;
      -- Starting flag
      startingDispatch : in  sl;
      -- Axi-Lite Registers
      axilReadMaster   : in  AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
      axilReadSlave    : out AxiLiteReadSlaveType;
      axilWriteMaster  : in  AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
      axilWriteSlave   : out AxiLiteWriteSlaveType
      );
end entity WorkCompChecker;

architecture rtl of WorkCompChecker is

   type AxilRegType is record
      resetCounters  : sl;
      axilReadSlave  : AxiLiteReadSlaveType;
      axilWriteSlave : AxiLiteWriteSlaveType;
   end record AxilRegType;

   constant AXIL_REG_INIT_C : AxilRegType := (
      resetCounters  => '0',
      axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C,
      axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C
      );

   signal regR   : AxilRegType := AXIL_REG_INIT_C;
   signal regRin : AxilRegType;

   type RecStateType is (st0_idle, st1_received);

   type RecRegType is record
      state            : RecStateType;
      successCounter   : slv(DISPATCH_COUNTER_BITS_G-1 downto 0);
      unsuccessCounter : slv(DISPATCH_COUNTER_BITS_G-1 downto 0);
      status           : slv(4 downto 0);
      rxSlave          : RoceWorkCompSlaveType;
   end record RecRegType;

   constant REC_REG_INIT_C : RecRegType := (
      state            => st0_idle,
      successCounter   => (others => '0'),
      unsuccessCounter => (others => '0'),
      status           => (others => '0'),
      rxSlave          => ROCE_WORK_COMP_SLAVE_INIT_C
      );

   signal recR   : RecRegType := REC_REG_INIT_C;
   signal recRin : RecRegType;

begin  -- architecture rtl

   -----------------------------------------------------------------------------
   -- Axi-Lite Regs
   -----------------------------------------------------------------------------
   regComb : process (axilReadMaster, axilWriteMaster, recR.successCounter,
                      recR.unsuccessCounter, regR) is
      variable v      : AxilRegType;
      variable regCon : AxiLiteEndPointType;
   begin  -- process regComb

      v := regR;

      -- Determine the transaction type
      axiSlaveWaitTxn(regCon, axilWriteMaster, axilReadMaster, v.axilWriteSlave, v.axilReadSlave);

      -- Gen registers
      axiSlaveRegisterR(regCon, x"F00", 0, recR.successCounter);
      axiSlaveRegisterR(regCon, x"F04", 0, recR.unsuccessCounter);
      axiSlaveRegister(regCon, x"F08", 0, v.resetCounters);

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

   -----------------------------------------------------------------------------
   -- Checker
   -----------------------------------------------------------------------------
   recComb : process (WorkCompMaster.status, WorkCompMaster.valid, recR,
                      regR.resetCounters) is
      variable v : recRegType;
   begin  -- process recComb

      -- Latch the current value
      v := recR;

      -- init ready
      v.rxSlave.ready := '0';

      -- Reset counters
      if regR.resetCounters = '1' then
         v.successCounter   := (others => '0');
         v.unsuccessCounter := (others => '0');
      end if;

      -- FSM
      case recR.state is
         -------------------------------------------------------------------------
         when st0_idle =>
            if WorkCompMaster.valid = '1' then
               v.rxSlave.ready := '1';
               v.status        := WorkCompMaster.status;
               v.state         := st1_received;
            end if;
         -----------------------------------------------------------------------
         when st1_received =>
            if recR.status = "00000" then
               v.successCounter := recR.successCounter + 1;
               v.state          := st0_idle;
            else
               v.unsuccessCounter := recR.unsuccessCounter + 1;
               v.state            := st0_idle;
            end if;
         -----------------------------------------------------------------------
         when others =>
            v := REC_REG_INIT_C;
      end case;

      WorkCompSlave <= v.rxSlave;

      recRin <= v;

   end process recComb;

   recSeq : process (RoceClk, RoceRst) is
   begin
      if (RST_ASYNC_G) and (RoceRst = '1') then
         recR <= REC_REG_INIT_C after TPD_G;
      elsif (rising_edge(RoceClk)) then
         if (RST_ASYNC_G = false) and (RoceRst = '1') then
            recR <= REC_REG_INIT_C after TPD_G;
         else
            recR <= recRin after TPD_G;
         end if;
      end if;
   end process recSeq;

end architecture rtl;

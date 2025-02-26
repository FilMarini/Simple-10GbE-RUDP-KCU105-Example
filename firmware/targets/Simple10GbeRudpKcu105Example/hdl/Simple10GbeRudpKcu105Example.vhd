-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Simple 10G-BASER Example
-------------------------------------------------------------------------------
-- This file is part of 'Simple-10GbE-RUDP-KCU105-Example'.
-- It is subject to the license terms in the LICENSE.txt file found in the
-- top-level directory of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'Simple-10GbE-RUDP-KCU105-Example', including this file,
-- may be copied, modified, propagated, or distributed except according to
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.AxiLitePkg.all;
use surf.RocePkg.all;

entity Simple10GbeRudpKcu105Example is
   generic (
      TPD_G             : time             := 1 ns;
      BUILD_INFO_G      : BuildInfoType;
      EXT_ROCE_CONFIG_G : boolean          := false;
      SIMULATION_G      : boolean          := false;
      IP_ADDR_G         : slv(31 downto 0) := x"0A02A8C0";  -- 192.168.2.10
      DHCP_G            : boolean          := false);
   port (
      -- I2C Ports
      sfpTxDisL  : out   sl;
      i2cRstL    : out   sl;
      i2cScl     : inout sl;
      i2cSda     : inout sl;
      -- XADC Ports
      vPIn       : in    sl;
      vNIn       : in    sl;
      -- System Ports
      emcClk     : in    sl;
      extRst     : in    sl;
      led        : out   slv(7 downto 0);
      -- Boot Memory Ports
      flashCsL   : out   sl;
      flashMosi  : out   sl;
      flashMiso  : in    sl;
      flashHoldL : out   sl;
      flashWp    : out   sl;
      -- ETH GT Pins
      ethClkP    : in    sl;
      ethClkN    : in    sl;
      ethRxP     : in    sl;
      ethRxN     : in    sl;
      ethTxP     : out   sl;
      ethTxN     : out   sl);
end Simple10GbeRudpKcu105Example;

architecture top_level of Simple10GbeRudpKcu105Example is

   signal heartbeat  : sl;
   signal phyReady   : sl;
   signal rssiLinkUp : slv(1 downto 0);

   -- Clock and Reset
   signal axilClk : sl;
   signal axilRst : sl;

   -- AXI-Stream: Stream Interface
   signal ibRudpMaster : AxiStreamMasterType;
   signal ibRudpSlave  : AxiStreamSlaveType;
   signal obRudpMaster : AxiStreamMasterType;
   signal obRudpSlave  : AxiStreamSlaveType;
   signal ibRoceMaster : AxiStreamMasterType;
   signal ibRoceSlave  : AxiStreamSlaveType;
   signal obRoceMaster : AxiStreamMasterType;
   signal obRoceSlave  : AxiStreamSlaveType;

   -- Axi-Lite XBAR Config
   constant NUM_AXIL_MASTERS_C : positive := 3;
   constant XBAR_CONFIG_C      : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0)
      := genAxiLiteConfig(NUM_AXIL_MASTERS_C, x"8000_0000", 31, 24);  -- 2^7 Slaves
   constant APP             : natural := 0;  -- 80xx_xxxx
   constant ROCE_DISPATCHER : natural := 1;  -- 81xx_xxxx
   constant ROCE_CHECKER    : natural := 2;  -- 82xx_xxxx

   -- AXI-Lite: Register Access
   signal axilReadMaster   : AxiLiteReadMasterType;
   signal axilReadSlave    : AxiLiteReadSlaveType;
   signal axilWriteMaster  : AxiLiteWriteMasterType;
   signal axilWriteSlave   : AxiLiteWriteSlaveType;
   signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0);
   signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0);

   -- RoCE
   signal workReqMaster            : RoceWorkReqMasterType;
   signal workReqSlave             : RoceWorkReqSlaveType;
   signal workCompMaster           : RoceWorkCompMasterType;
   signal workCompSlave            : RoceWorkCompSlaveType;
   signal dmaReadRespMaster        : RoceDmaReadRespMasterType;
   signal dmaReadRespSlave         : RoceDmaReadRespSlaveType;
   signal dmaReadReqMaster         : RoceDmaReadReqMasterType;
   signal dmaReadReqSlave          : RoceDmaReadReqSlaveType;
   signal startingDispatch         : std_logic;
   signal startingDispatchLedPulse : std_logic;

begin

   led(7) <= '1';
   led(6) <= '0';
   led(5) <= heartbeat;
   led(4) <= axilRst;
   led(3) <= not(axilRst);
   led(2) <= rssiLinkUp(1);
   led(1) <= rssiLinkUp(0);
   led(0) <= phyReady;

   -----------------------
   -- Core Firmware Module
   -----------------------
   U_Core : entity work.Core
      generic map (
         TPD_G        => TPD_G,
         BUILD_INFO_G => BUILD_INFO_G,
         SIMULATION_G => SIMULATION_G,
         BUILD_10G_G  => true,          -- 10GbE
         IP_ADDR_G    => IP_ADDR_G,
         DHCP_G       => DHCP_G)
      port map (
         -- Clock and Reset
         axilClk           => axilClk,
         axilRst           => axilRst,
         -- AXI-Stream Interface
         ibRudpMaster      => ibRudpMaster,
         ibRudpSlave       => ibRudpSlave,
         obRudpMaster      => obRudpMaster,
         obRudpSlave       => obRudpSlave,
         -- RoCE engine Interface
         workReqMaster     => workReqMaster,
         workReqSlave      => workReqSlave,
         workCompMaster    => workCompMaster,
         workCompSlave     => workCompSlave,
         dmaReadRespMaster => dmaReadRespMaster,
         dmaReadRespSlave  => dmaReadRespSlave,
         dmaReadReqMaster  => dmaReadReqMaster,
         dmaReadReqSlave   => dmaReadReqSlave,
         -- AXI-Lite Interface
         axilReadMaster    => axilReadMaster,
         axilReadSlave     => axilReadSlave,
         axilWriteMaster   => axilWriteMaster,
         axilWriteSlave    => axilWriteSlave,
         -- I2C Ports
         sfpTxDisL         => sfpTxDisL,
         i2cRstL           => i2cRstL,
         i2cScl            => i2cScl,
         i2cSda            => i2cSda,
         -- SYSMON Ports
         vPIn              => vPIn,
         vNIn              => vNIn,
         -- System Ports
         extRst            => extRst,
         emcClk            => emcClk,
         heartbeat         => heartbeat,
         phyReady          => phyReady,
         rssiLinkUp        => rssiLinkUp,
         -- Boot Memory Ports
         flashCsL          => flashCsL,
         flashMosi         => flashMosi,
         flashMiso         => flashMiso,
         flashHoldL        => flashHoldL,
         flashWp           => flashWp,
         -- ETH GT Pins
         ethClkP           => ethClkP,
         ethClkN           => ethClkN,
         ethRxP            => ethRxP,
         ethRxN            => ethRxN,
         ethTxP            => ethTxP,
         ethTxN            => ethTxN);

   -----------------------
   -- AXI Lite Crossbar
   -----------------------
   AxiLiteCrossbar_1 : entity surf.AxiLiteCrossbar
      generic map (
         NUM_SLAVE_SLOTS_G  => 1,
         NUM_MASTER_SLOTS_G => NUM_AXIL_MASTERS_C,
         MASTERS_CONFIG_G   => XBAR_CONFIG_C,
         DEBUG_G            => false
         )
      port map (
         axiClk           => axilClk,
         axiClkRst        => axilRst,
         sAxiWriteMasters => axilWriteMaster,
         sAxiWriteSlaves  => axilWriteSlave,
         sAxiReadMasters  => axilReadMaster,
         sAxiReadSlaves   => axilReadSlave,
         mAxiWriteMasters => axilWriteMasters,  --o
         mAxiWriteSlaves  => axilWriteSlaves,   --i
         mAxiReadMasters  => axilReadMasters,   --o
         mAxiReadSlaves   => axilReadSlaves     --i
         );

   ------------------------------
   -- Application Firmware Module
   ------------------------------
   U_App : entity work.App
      generic map (
         TPD_G        => TPD_G,
         SIMULATION_G => SIMULATION_G)
      port map (
         -- Clock and Reset
         axilClk         => axilClk,
         axilRst         => axilRst,
         -- AXI-Stream Interface
         ibRudpMaster    => ibRudpMaster,
         ibRudpSlave     => ibRudpSlave,
         obRudpMaster    => obRudpMaster,
         obRudpSlave     => obRudpSlave,
         -- AXI-Lite Interface
         axilReadMaster  => axilReadMasters(APP),
         axilReadSlave   => axilReadSlaves(APP),
         axilWriteMaster => axilWriteMasters(APP),
         axilWriteSlave  => axilWriteSlaves(APP));

   ------------------------
   -- RoCE Dma Dummy Server
   ------------------------
   DmaDummyServer_1 : entity work.DmaDummyServer
      generic map (
         TPD_G => TPD_G)
      port map (
         RoceClk             => axilClk,
         RoceRst             => axilRst,
         dmaReadReqMaster_i  => dmaReadReqMaster,
         dmaReadReqSlave_o   => dmaReadReqSlave,
         dmaReadRespMaster_o => dmaReadRespMaster,
         dmaReadRespSlave_i  => dmaReadRespSlave
         );

   --------------------
   -- WorkReqDispatcher
   --------------------
   WorkReqDispatcher_1 : entity work.WorkReqDispatcher
      generic map (
         TPD_G => TPD_G)
      port map (
         RoceClk            => axilClk,
         RoceRst            => axilRst,
         workReqMaster_o    => workReqMaster,
         workReqSlave_i     => workReqSlave,
         startingDispatch_o => startingDispatch,
         axilReadMaster     => axilReadMastersX(ROCE_DISPATCHER),
         axilReadSlave      => axilReadSlavesX(ROCE_DISPATCHER),
         axilWriteMaster    => axilWriteMastersX(ROCE_DISPATCHER),
         axilWriteSlave     => axilWriteSlavesX(ROCE_DISPATCHER)
         );

   ------------------
   -- WorkCompChecker
   ------------------
   WorkCompChecker_1 : entity work.WorkCompChecker
      generic map (
         TPD_G => TPD_G
         )
      port map (
         RoceClk          => axilClk,
         RoceRst          => axilRst,
         WorkCompMaster   => workCompMaster,
         WorkCompSlave    => workCompSlave,
         startingDispatch => startingDispatch,
         axilReadMaster   => axilReadMastersX(ROCE_CHECKER),
         axilReadSlave    => axilReadSlavesX(ROCE_CHECKER),
         axilWriteMaster  => axilWriteMastersX(ROCE_CHECKER),
         axilWriteSlave   => axilWriteSlavesX(ROCE_CHECKER)
         );

end top_level;
